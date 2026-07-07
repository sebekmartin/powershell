[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TeamId,

    [Parameter(Mandatory = $false)]
    [string]$TeamName,

    [Parameter(Mandatory = $false)]
    [string]$TeamsCsvPath,

    [Parameter(Mandatory = $false)]
    [string]$ChannelName,

    [Parameter(Mandatory = $false)]
    [string[]]$AllowedChannelKeywords = @("audit", "pbc"),

    [Parameter(Mandatory = $false)]
    [string[]]$MemberUpns,

    [Parameter(Mandatory = $false)]
    [string]$UsersCsvPath,

    [Parameter(Mandatory = $false)]
    [string[]]$OwnerUpns,

    [Parameter(Mandatory = $false)]
    [string]$OwnersCsvPath,

    [Parameter(Mandatory = $false)]
    [string]$FallbackOwnerUpn = "milan.nemec@grinex.cz",

    [switch]$EnsureTeamMembership,

    [switch]$SkipConnect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RestoreChannelStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Get-ElapsedLabel {
    param(
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    return ('{0:mm\:ss}' -f $Stopwatch.Elapsed)
}

function Write-StatusLine {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host "[$(Get-ElapsedLabel -Stopwatch $script:RestoreChannelStopwatch)] $Message" -ForegroundColor $Color
}

function Get-NormalizedUpns {
    param(
        [string[]]$InlineUpns,
        [string]$CsvPath
    )

    $upns = @()

    if ($InlineUpns) {
        $upns += $InlineUpns
    }

    if ($CsvPath) {
        if (-not (Test-Path -LiteralPath $CsvPath)) {
            throw "CSV file was not found: $CsvPath"
        }

        $rows = Import-Csv -Path $CsvPath
        foreach ($row in $rows) {
            if ($row.UserPrincipalName) {
                $upns += $row.UserPrincipalName
                continue
            }

            if ($row.UPN) {
                $upns += $row.UPN
                continue
            }

            if ($row.User) {
                $upns += $row.User
                continue
            }

            throw "CSV must contain one of these columns: UserPrincipalName, UPN, User"
        }
    }

    $normalized = $upns |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -ne "" } |
        Sort-Object -Unique

    return $normalized
}

function Get-NormalizedIdentityKey {
    param(
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized -eq "") {
        return $null
    }

    if ($normalized.Contains("\\")) {
        $normalized = ($normalized -split "\\")[-1]
    }

    if ($normalized.Contains("@")) {
        return ($normalized -split "@")[0]
    }

    return $normalized
}

function Get-UserIdentityFromObject {
    param(
        [object]$InputObject
    )

    foreach ($propName in @("UserPrincipalName", "User", "Email", "Mail", "Username", "Name")) {
        $prop = $InputObject.PSObject.Properties[$propName]
        if ($prop -and $prop.Value) {
            $value = $prop.Value.ToString().Trim().ToLowerInvariant()
            if ($value -ne "") {
                return $value
            }
        }
    }

    return $null
}

function Get-RequestedTeamsFromCsv {
    param(
        [string]$CsvPath
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        throw "CSV file was not found: $CsvPath"
    }

    $lines = @(Get-Content -LiteralPath $CsvPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    $requestedTeams = @()

    if (@($lines).Count -eq 0) {
        throw "Teams CSV is empty: $CsvPath"
    }

    $firstLine = $lines[0]
    $knownHeaders = @("TeamId", "GroupId", "Id", "TeamName", "DisplayName", "Name")
    $headerPattern = '^(?i)(TeamId|GroupId|Id|TeamName|DisplayName|Name)(\s*[,;]\s*(TeamId|GroupId|Id|TeamName|DisplayName|Name))*$'

    if ($firstLine -notmatch $headerPattern) {
        $teamNameLines = $lines

        foreach ($line in $teamNameLines) {
            $requestedTeams += [PSCustomObject]@{
                TeamId   = $null
                TeamName = $line
            }
        }

        return @($requestedTeams)
    }

    $rows = Import-Csv -Path $CsvPath

    foreach ($row in $rows) {
        $teamIdValue = $null
        foreach ($columnName in @("TeamId", "GroupId", "Id")) {
            $prop = $row.PSObject.Properties[$columnName]
            if ($prop -and $prop.Value) {
                $candidate = $prop.Value.ToString().Trim()
                if ($candidate -ne "") {
                    $teamIdValue = $candidate
                    break
                }
            }
        }

        $teamNameValue = $null
        foreach ($columnName in @("TeamName", "DisplayName", "Name")) {
            $prop = $row.PSObject.Properties[$columnName]
            if ($prop -and $prop.Value) {
                $candidate = $prop.Value.ToString().Trim()
                if ($candidate -ne "") {
                    $teamNameValue = $candidate
                    break
                }
            }
        }

        if (-not $teamIdValue -and -not $teamNameValue) {
            throw "Teams CSV must contain at least one of these columns per row: TeamId, GroupId, Id, TeamName, DisplayName, Name"
        }

        $requestedTeams += [PSCustomObject]@{
            TeamId   = $teamIdValue
            TeamName = $teamNameValue
        }
    }

    return @($requestedTeams)
}

function Select-TeamFromCandidates {
    param(
        [string]$RequestedTeamName,
        [object[]]$Candidates
    )

    $candidateTeams = @($Candidates)
    if (@($candidateTeams).Count -eq 0) {
        return $null
    }

    if (@($candidateTeams).Count -eq 1) {
        return $candidateTeams[0]
    }

    Write-Warning "Multiple Teams found with name '$RequestedTeamName'."
    Write-Host "Select TeamId to continue (or type 'skip' to skip this team):" -ForegroundColor Yellow
    foreach ($candidate in $candidateTeams) {
        Write-Host "  TeamId: $($candidate.GroupId) | DisplayName: $($candidate.DisplayName)" -ForegroundColor DarkYellow
    }

    while ($true) {
        $selectedTeamId = Read-Host "Enter TeamId"
        if (-not $selectedTeamId) {
            Write-Warning "No TeamId entered. Try again or type 'skip'."
            continue
        }

        $selectedTeamId = $selectedTeamId.Trim()
        if ($selectedTeamId.ToLowerInvariant() -eq "skip") {
            return $null
        }

        $selectedMatches = @(
            $candidateTeams |
                Where-Object {
                    $_.GroupId -and $_.GroupId.ToString().Trim().ToLowerInvariant() -eq $selectedTeamId.ToLowerInvariant()
                }
        )

        if (@($selectedMatches).Count -eq 1) {
            return $selectedMatches[0]
        }

        Write-Warning "TeamId '$selectedTeamId' is not one of the listed candidates."
    }
}

function Resolve-TeamIdentityMatch {
    param(
        [string]$RequestedUser,
        [string[]]$ResolvedTeamUsers
    )

    $requestedKey = Get-NormalizedIdentityKey -Value $RequestedUser
    foreach ($resolvedUser in $ResolvedTeamUsers) {
        if ($resolvedUser -eq $RequestedUser) {
            return $resolvedUser
        }

        if ((Get-NormalizedIdentityKey -Value $resolvedUser) -eq $requestedKey) {
            return $resolvedUser
        }
    }

    return $null
}

function Add-UserToTeamIfMissing {
    param(
        [string]$GroupId,
        [string]$User
    )

    $targetKey = Get-NormalizedIdentityKey -Value $User

    $existing = Get-TeamUser -GroupId $GroupId -ErrorAction SilentlyContinue |
        Where-Object {
            $resolvedIdentity = Get-UserIdentityFromObject -InputObject $_
            if (-not $resolvedIdentity) {
                return $false
            }

            ($resolvedIdentity -eq $User) -or ((Get-NormalizedIdentityKey -Value $resolvedIdentity) -eq $targetKey)
        } |
        Select-Object -First 1

    if (-not $existing) {
        try {
            Add-TeamUser -GroupId $GroupId -User $User -Role Member -ErrorAction Stop
            Write-Host "  Added to Team: $User" -ForegroundColor DarkCyan
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match "already" -or $message -match "exists") {
                Write-Host "  Already in Team: $User" -ForegroundColor Yellow
                return
            }

            Write-Warning "  Failed to add '$User' to Team '$GroupId': $message"
        }
    }
}

function Add-UserToPrivateChannel {
    param(
        [string]$GroupId,
        [string]$ChannelDisplayName,
        [string]$User,
        [string]$Role,
        [object[]]$ExistingChannelUsers
    )

    if ($Role -notin @("Owner", "Member")) {
        throw "Unsupported channel role '$Role'. Allowed values: Owner, Member"
    }

    $targetKey = Get-NormalizedIdentityKey -Value $User
    $channelUsers = if ($null -ne $ExistingChannelUsers) {
        @($ExistingChannelUsers)
    }
    else {
        @(Get-TeamChannelUser -GroupId $GroupId -DisplayName $ChannelDisplayName -ErrorAction SilentlyContinue)
    }

    $existingChannelUser = $channelUsers |
        Where-Object {
            $resolvedIdentity = Get-UserIdentityFromObject -InputObject $_
            if (-not $resolvedIdentity) {
                return $false
            }

            ($resolvedIdentity -eq $User) -or ((Get-NormalizedIdentityKey -Value $resolvedIdentity) -eq $targetKey)
        } |
        Select-Object -First 1

    if ($existingChannelUser) {
        $existingRole = "Member"
        $roleProp = $existingChannelUser.PSObject.Properties['Role']
        if ($roleProp -and $roleProp.Value) {
            $existingRole = $roleProp.Value.ToString()
        }

        if ($Role -eq "Member") {
            Write-Host "    Already present ($existingRole): $User" -ForegroundColor Yellow
            return $false
        }

        if ($existingRole.ToLowerInvariant() -eq "owner") {
            Write-Host "    Already present (Owner): $User" -ForegroundColor Yellow
            return $false
        }
    }

    # Step 1: Ensure the user is present in the private channel as member.
    $addAttempts = 3
    for ($attempt = 1; $attempt -le $addAttempts; $attempt++) {
        try {
            Write-StatusLine "Adding member to channel: $User" DarkCyan
            Add-TeamChannelUser -GroupId $GroupId -DisplayName $ChannelDisplayName -User $User -ErrorAction Stop
            break
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match "already" -or $message -match "exists") {
                break
            }

            $isTransient = $message -match "BadGateway" -or $message -match "HttpStatusCode:\s*BadGateway" -or $message -match "TooManyRequests" -or $message -match "HttpStatusCode:\s*TooManyRequests" -or $message -match "temporar" -or $message -match "try again"
            if ($isTransient -and $attempt -lt $addAttempts) {
                $retryDelay = $attempt
                Write-Warning "    Transient error while adding member '$User' (attempt $attempt/$addAttempts). Waiting $retryDelay s before retry..."
                Start-Sleep -Seconds $attempt
                continue
            }

            Write-Warning "    Failed to add '$User' to channel '$ChannelDisplayName': $message"
            return $false
        }
    }

    if ($Role -eq "Member") {
        Write-Host "    Added Member: $User" -ForegroundColor Green
        return $true
    }

    # Step 2: Promote selected users to Owner.
    Start-Sleep -Seconds 1
    $ownerAttempts = 3
    for ($attempt = 1; $attempt -le $ownerAttempts; $attempt++) {
        try {
            Write-StatusLine "Promoting to owner in channel: $User" DarkCyan
            Add-TeamChannelUser -GroupId $GroupId -DisplayName $ChannelDisplayName -User $User -Role Owner -ErrorAction Stop
            Write-Host "    Added Owner: $User" -ForegroundColor Green
            return $true
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match "already" -or $message -match "exists") {
                Write-Host "    Already present (Owner): $User" -ForegroundColor Yellow
                return $false
            }

            $isTransient = $message -match "BadGateway" -or $message -match "HttpStatusCode:\s*BadGateway" -or $message -match "TooManyRequests" -or $message -match "HttpStatusCode:\s*TooManyRequests" -or $message -match "temporar" -or $message -match "try again"
            if ($isTransient -and $attempt -lt $ownerAttempts) {
                $retryDelay = 2 * $attempt
                Write-Warning "    Transient error while promoting '$User' to Owner (attempt $attempt/$ownerAttempts). Waiting $retryDelay s before retry..."
                Start-Sleep -Seconds $retryDelay
                continue
            }

            Write-Warning "    Failed to promote '$User' to Owner in channel '$ChannelDisplayName': $message"
            return $false
        }
    }

    return $false
}

if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
    throw "Module 'MicrosoftTeams' is not installed. Install it first: Install-Module MicrosoftTeams -Scope CurrentUser"
}

if (-not $MemberUpns -and -not $UsersCsvPath) {
    throw "Provide users either via -MemberUpns or -UsersCsvPath"
}

if (($TeamId -and $TeamName) -or (($TeamId -or $TeamName) -and $TeamsCsvPath)) {
    throw "Use either -TeamId/-TeamName for one team or -TeamsCsvPath for multiple teams, not both"
}

if ($TeamId -and $TeamName) {
    throw "Use either -TeamId or -TeamName, not both"
}

$owners = @(Get-NormalizedUpns -InlineUpns $OwnerUpns -CsvPath $OwnersCsvPath)

if (@($owners).Count -eq 0) {
    throw "Provide owners via -OwnerUpns or -OwnersCsvPath"
}

$members = @(Get-NormalizedUpns -InlineUpns $MemberUpns -CsvPath $UsersCsvPath)
$members = @($members | Where-Object { $_ -notin $owners })
$requestedUsers = @(@($owners) + @($members))
$requestedUsers = @($requestedUsers | Sort-Object -Unique)
$fallbackOwner = $FallbackOwnerUpn.Trim().ToLowerInvariant()

if (-not $SkipConnect) {
    Write-StatusLine "Connecting to Microsoft Teams..." Cyan
    Connect-MicrosoftTeams | Out-Null
}
else {
    Write-StatusLine "Skipping Connect-MicrosoftTeams (using existing session)." Cyan
}

if ($TeamId) {
    $requestedTeams = @([PSCustomObject]@{ TeamId = $TeamId; TeamName = $TeamName })
}
elseif ($TeamsCsvPath) {
    Write-StatusLine "Loading teams from CSV: $TeamsCsvPath" Cyan
    $requestedTeams = @(Get-RequestedTeamsFromCsv -CsvPath $TeamsCsvPath)
}
elseif ($TeamName) {
    $requestedTeams = @([PSCustomObject]@{ TeamId = $null; TeamName = $TeamName })
}
else {
    $requestedTeams = @((Get-Team) | ForEach-Object { [PSCustomObject]@{ TeamId = $_.GroupId; TeamName = $_.DisplayName } })
}

if (@($requestedTeams).Count -eq 0) {
    throw "No Teams requested for processing."
}

if (@($AllowedChannelKeywords).Count -eq 0) {
    throw "Provide at least one value for -AllowedChannelKeywords"
}

$keywordRegex = "(?i)(" + (($AllowedChannelKeywords | ForEach-Object { [Regex]::Escape($_) }) -join "|") + ")"

$totalChannelsFound = 0
$totalTeamsProcessed = 0
$addedOwnerCount = 0
$addedMemberCount = 0
$teamMembershipEnsured = @{}

foreach ($requestedTeam in $requestedTeams) {
    $team = $null

    if ($requestedTeam.TeamId) {
        Write-StatusLine "Loading team by GroupId: $($requestedTeam.TeamId)" Cyan
        $team = Get-Team -GroupId $requestedTeam.TeamId
    }
    elseif ($requestedTeam.TeamName) {
        Write-StatusLine "Looking up Team by name: $($requestedTeam.TeamName)" Cyan
        $teamCandidates = @(Get-Team -DisplayName $requestedTeam.TeamName -ErrorAction SilentlyContinue)
        $team = @($teamCandidates | Where-Object { $_.DisplayName -ceq $requestedTeam.TeamName })

        if (@($team).Count -eq 0) {
            # Fallback for tenants/modules where DisplayName filtering can be inconsistent.
            $team = @(Get-Team | Where-Object { $_.DisplayName -ceq $requestedTeam.TeamName })
        }

        if (@($team).Count -gt 1) {
            $team = Select-TeamFromCandidates -RequestedTeamName $requestedTeam.TeamName -Candidates $team
            if (-not $team) {
                Write-Warning "Team '$($requestedTeam.TeamName)' was skipped by user."
                continue
            }
        }

        if (@($team).Count -eq 1) {
            $team = $team[0]
        }
    }

    if (-not $team) {
        Write-Warning "Requested team was not found, skipping. TeamId='$($requestedTeam.TeamId)' TeamName='$($requestedTeam.TeamName)'"
        continue
    }

    $totalTeamsProcessed++

    Write-StatusLine "Scanning team: $($team.DisplayName)" Magenta
    $teamUsers = @(Get-TeamUser -GroupId $team.GroupId -ErrorAction SilentlyContinue)

    $teamMemberUpns = @(
        $teamUsers |
            ForEach-Object {
                Get-UserIdentityFromObject -InputObject $_
            } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $teamMemberKeys = @(
        $teamMemberUpns |
            ForEach-Object { Get-NormalizedIdentityKey -Value $_ } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $teamOwnerUpns = @(
        $teamUsers |
            Where-Object {
                $roleProp = $_.PSObject.Properties['Role']
                $roleProp -and $roleProp.Value -and $roleProp.Value.ToString().ToLowerInvariant() -eq "owner"
            } |
            ForEach-Object {
                Get-UserIdentityFromObject -InputObject $_
            } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $teamOwnerKeys = @(
        $teamOwnerUpns |
            ForEach-Object { Get-NormalizedIdentityKey -Value $_ } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $eligibleUsers = @(
        $requestedUsers |
            Where-Object {
                ($_ -in $teamMemberUpns) -or ((Get-NormalizedIdentityKey -Value $_) -in $teamMemberKeys)
            }
    )

    $eligibleOwnerCandidates = @(
        $owners |
            Where-Object {
                ($_ -in $teamMemberUpns) -or ((Get-NormalizedIdentityKey -Value $_) -in $teamMemberKeys)
            }
    )

    $eligibleMemberUsers = @(
        $members |
            Where-Object {
                ($_ -in $teamMemberUpns) -or ((Get-NormalizedIdentityKey -Value $_) -in $teamMemberKeys)
            }
    )

    if ((@($eligibleOwnerCandidates).Count + @($eligibleMemberUsers).Count) -eq 0) {
        Write-Warning "No eligible CSV users are current members of Team '$($team.DisplayName)'. Skipping this Team."
        Write-Host "  CSV requested: $(@($requestedUsers).Count), Team members resolved: $(@($teamMemberUpns).Count)" -ForegroundColor DarkYellow
        continue
    }

    $ownersForChannels = @(
        $eligibleOwnerCandidates |
            Where-Object {
                (
                    ($_ -in $teamOwnerUpns) -or
                    ((Get-NormalizedIdentityKey -Value $_) -in $teamOwnerKeys)
                )
            }
    )

    # If a requested member is already Team owner, keep Owner role in private channels.
    $ownerMembers = @(
        $eligibleMemberUsers |
            Where-Object {
                (
                    ($_ -in $teamOwnerUpns) -or
                    ((Get-NormalizedIdentityKey -Value $_) -in $teamOwnerKeys)
                )
            }
    )

    if (@($ownerMembers).Count -gt 0) {
        $ownersForChannels = @(@($ownersForChannels) + @($ownerMembers) | Sort-Object -Unique)
    }
    if (@($ownersForChannels).Count -eq 0) {
        if (($fallbackOwner -in $eligibleOwnerCandidates) -or ((Get-NormalizedIdentityKey -Value $fallbackOwner) -in ($eligibleOwnerCandidates | ForEach-Object { Get-NormalizedIdentityKey -Value $_ }))) {
            $ownersForChannels = @($fallbackOwner)
            Write-Host "Using fallback private channel owner for Team '$($team.DisplayName)': $fallbackOwner" -ForegroundColor DarkYellow
        }
        else {
            Write-Warning "No Team owner from your CSV list found for Team '$($team.DisplayName)', and fallback owner '$fallbackOwner' is not an eligible team member from CSV."
        }
    }

    $ownerKeysForChannels = @(
        $ownersForChannels |
            ForEach-Object { Get-NormalizedIdentityKey -Value $_ } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $membersForChannels = @(
        $eligibleMemberUsers |
            Where-Object {
                $memberKey = Get-NormalizedIdentityKey -Value $_
                ($memberKey) -and ($memberKey -notin $ownerKeysForChannels)
            }
    )

    Write-Host "Resolved for Team '$($team.DisplayName)' -> Owners: $((@($ownersForChannels) -join ', ')); Members: $((@($membersForChannels) -join ', '))" -ForegroundColor DarkGray

    foreach ($resolvedOwner in $ownersForChannels) {
        $matchedIdentity = Resolve-TeamIdentityMatch -RequestedUser $resolvedOwner -ResolvedTeamUsers $teamOwnerUpns
        if (-not $matchedIdentity) {
            $matchedIdentity = Resolve-TeamIdentityMatch -RequestedUser $resolvedOwner -ResolvedTeamUsers $teamMemberUpns
        }

        if ($matchedIdentity) {
            Write-Host "  Owner match: $resolvedOwner <= $matchedIdentity" -ForegroundColor DarkGray
        }
    }

    foreach ($resolvedMember in $membersForChannels) {
        $matchedIdentity = Resolve-TeamIdentityMatch -RequestedUser $resolvedMember -ResolvedTeamUsers $teamMemberUpns
        if ($matchedIdentity) {
            Write-Host "  Member match: $resolvedMember <= $matchedIdentity" -ForegroundColor DarkGray
        }
    }

    $privateChannels = Get-TeamChannel -GroupId $team.GroupId | Where-Object { $_.MembershipType -eq "Private" }

    $privateChannels = $privateChannels | Where-Object {
        $_.DisplayName -and $_.DisplayName -match $keywordRegex
    }

    if ($ChannelName) {
        $privateChannels = $privateChannels | Where-Object { $_.DisplayName -like "*$ChannelName*" }
    }

    if (@($privateChannels).Count -eq 0) {
        Write-Warning "No private channels matched the selected scope/filter for Team '$($team.DisplayName)'."
        continue
    }

    Write-Host "Found $(@($privateChannels).Count) private channel(s) for Team '$($team.DisplayName)'." -ForegroundColor Cyan

    foreach ($channel in $privateChannels) {
        $scopeLabel = "$($team.DisplayName) / $($channel.DisplayName)"
        if (-not $PSCmdlet.ShouldProcess($scopeLabel, "Restore channel membership")) {
            continue
        }

        $totalChannelsFound++

        if ((@($ownersForChannels).Count -eq 0) -and (@($membersForChannels).Count -eq 0)) {
            Write-Host "Skipping: $scopeLabel (no eligible CSV users are current team members)" -ForegroundColor DarkYellow
            continue
        }

        if ($EnsureTeamMembership -and -not $teamMembershipEnsured.ContainsKey($team.GroupId)) {
            foreach ($owner in $ownersForChannels) {
                Add-UserToTeamIfMissing -GroupId $team.GroupId -User $owner
            }

            foreach ($member in $membersForChannels) {
                Add-UserToTeamIfMissing -GroupId $team.GroupId -User $member
            }

            $teamMembershipEnsured[$team.GroupId] = $true
        }

        Write-Host "Processing: $scopeLabel" -ForegroundColor Magenta
        $existingChannelUsers = @(Get-TeamChannelUser -GroupId $team.GroupId -DisplayName $channel.DisplayName -ErrorAction SilentlyContinue)

        foreach ($owner in $ownersForChannels) {
            if (Add-UserToPrivateChannel -GroupId $team.GroupId -ChannelDisplayName $channel.DisplayName -User $owner -Role "Owner" -ExistingChannelUsers $existingChannelUsers) {
                $addedOwnerCount++
            }
        }

        foreach ($member in $membersForChannels) {
            if (Add-UserToPrivateChannel -GroupId $team.GroupId -ChannelDisplayName $channel.DisplayName -User $member -Role "Member" -ExistingChannelUsers $existingChannelUsers) {
                $addedMemberCount++
            }
        }
    }
}

if ($totalChannelsFound -eq 0) {
    Write-Warning "No private channels matched the selected scope/filter."
    return
}

Write-Host "Done." -ForegroundColor Cyan
Write-StatusLine "Processed $totalTeamsProcessed team(s) and $totalChannelsFound channel(s)" Cyan
Write-StatusLine "Total elapsed: $(Get-ElapsedLabel -Stopwatch $script:RestoreChannelStopwatch)" Cyan
Write-Host "Owners added: $addedOwnerCount" -ForegroundColor Cyan
Write-Host "Members added: $addedMemberCount" -ForegroundColor Cyan
