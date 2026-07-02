[CmdletBinding(DefaultParameterSetName = 'ByObjectId')]
param (
  [Parameter(Mandatory = $true, ParameterSetName = 'ByObjectId')]
  [ValidateNotNullOrEmpty()]
  [string]$GroupObjectId,

  [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
  [ValidateNotNullOrEmpty()]
  [string]$GroupName,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$Filter,

  [switch]$NoConnect
)

function Ensure-GraphConnection {
  param (
    [string[]]$RequiredScopes
  )

  $context = Get-MgContext
  if (-not $context) {
    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
    return
  }

  $missingScopes = $RequiredScopes | Where-Object { $context.Scopes -notcontains $_ }
  if ($missingScopes.Count -gt 0) {
    Write-Host "Reconnecting to Microsoft Graph to request missing scopes: $($missingScopes -join ', ')" -ForegroundColor Yellow
    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
  }
}

try {
  $commandsToCheck = @('Get-MgContext', 'Connect-MgGraph', 'Get-MgGroup', 'Get-MgUser', 'New-MgGroupMemberByRef')
  foreach ($commandName in $commandsToCheck) {
    if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
      throw "Required command '$commandName' was not found. Install Microsoft Graph PowerShell SDK (Microsoft.Graph module)."
    }
  }

  if (-not $NoConnect) {
    Ensure-GraphConnection -RequiredScopes @('Group.Read.All', 'GroupMember.ReadWrite.All', 'User.Read.All')
  }

  $group = $null

  if ($PSCmdlet.ParameterSetName -eq 'ByObjectId') {
    $group = Get-MgGroup -GroupId $GroupObjectId -ErrorAction Stop
  }
  else {
    $escapedGroupName = $GroupName.Replace("'", "''")
    Write-Host "Searching for group with displayName '$escapedGroupName'..." -ForegroundColor Cyan
    $groups = Get-MgGroup -Filter "displayName eq '$escapedGroupName'" -All -ConsistencyLevel eventual
    Write-Host "Groups: $($groups -join ', ')" -ForegroundColor Cyan

    if (-not $groups) {
      throw "No group found with displayName '$GroupName'."
    }

    if ($groups.Count -gt 1) {
      $matches = $groups | Select-Object -ExpandProperty Id
      throw "Multiple groups found with displayName '$GroupName'. Use -GroupObjectId. Matching IDs: $($matches -join ', ')"
    }

    $group = $groups
  }

  Write-Host "Target group: $($group.DisplayName) ($($group.Id))" -ForegroundColor Cyan
  Write-Host "User filter: $Filter" -ForegroundColor Cyan

  # Keep filter behavior aligned with Entra/Graph OData -Filter syntax by passing it directly.
  $users = Get-MgUser -Filter $Filter -All -ConsistencyLevel eventual -ErrorAction Stop

  if (-not $users) {
    Write-Warning "No users matched the provided filter."
    return
  }

  $addedCount = 0
  $alreadyMemberCount = 0
  $failedCount = 0

  foreach ($user in $users) {
    $body = @{
      '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
    }

    try {
      New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter $body -ErrorAction Stop
      $addedCount++
      Write-Host "Added: $($user.UserPrincipalName)" -ForegroundColor Green
    }
    catch {
      $errorMessage = $_.Exception.Message

      if ($errorMessage -match 'added object references already exist') {
        $alreadyMemberCount++
        Write-Host "Already a member: $($user.UserPrincipalName)" -ForegroundColor DarkYellow
      }
      else {
        $failedCount++
        Write-Warning "Failed to add $($user.UserPrincipalName): $errorMessage"
      }
    }
  }

  Write-Host ''
  Write-Host 'Summary' -ForegroundColor Cyan
  Write-Host "Matched users:  $($users.Count)"
  Write-Host "Added users:    $addedCount"
  Write-Host "Already member: $alreadyMemberCount"
  Write-Host "Failed:         $failedCount"
}
catch {
  Write-Error $_
  exit 1
}
