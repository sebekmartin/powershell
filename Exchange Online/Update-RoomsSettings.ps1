param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath = ".\rooms-settings.csv",
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

function ConvertTo-BoolValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [System.Convert]::ToBoolean($Value)
}

function ConvertTo-IntValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [int]$Value
}

function ConvertTo-StringArray {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split "~" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Sync-FullAccessPermissions {
    param(
        [string]$Identity,
        [string[]]$DesiredUsers
    )

    $existingPermissions = Get-MailboxPermission -Identity $Identity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue |
    Where-Object { $_.IsInherited -eq $false -and $_.User.ToString() -ne "NT AUTHORITY\SELF" }

    foreach ($permission in $existingPermissions) {
        Remove-MailboxPermission -Identity $Identity -User $permission.User.ToString() -AccessRights $permission.AccessRights -InheritanceType $permission.InheritanceType -Confirm:$false -ErrorAction Stop
    }

    foreach ($user in $DesiredUsers) {
        Add-MailboxPermission -Identity $Identity -User $user -AccessRights FullAccess -InheritanceType All -AutoMapping:$false -Confirm:$false -ErrorAction Stop | Out-Null
    }
}

function Sync-SendAsPermissions {
    param(
        [string]$Identity,
        [string[]]$DesiredTrustees
    )

    $existingPermissions = Get-RecipientPermission -Identity $Identity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue |
    Where-Object { $_.IsInherited -eq $false -and $_.Trustee.ToString() -ne "NT AUTHORITY\SELF" }

    foreach ($permission in $existingPermissions) {
        Remove-RecipientPermission -Identity $Identity -Trustee $permission.Trustee.ToString() -AccessRights SendAs -Confirm:$false -ErrorAction Stop
    }

    foreach ($trustee in $DesiredTrustees) {
        Add-RecipientPermission -Identity $Identity -Trustee $trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
    }
}

function Sync-CalendarFolderPermissions {
    param(
        [string]$Identity,
        [string[]]$DesiredPermissions
    )

    $calendarFolder = Get-EXOMailboxFolderStatistics -Identity $Identity -FolderScope Calendar |
    Where-Object { $_.FolderType -eq "Calendar" } 

    if (-not $calendarFolder) {
        throw "Calendar folder was not found."
    }

    $folderIdentity = "${Identity}:\$($calendarFolder.Name)"
    $existingPermissions = Get-MailboxFolderPermission -Identity $folderIdentity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $existingPermissionsUsers = $existingPermissions | Select-Object User | Foreach-Object { $_.User.DisplayName }

    foreach ($entry in $DesiredPermissions) {
        $parts = $entry -split ":", 2
        if ($parts.Count -ne 2) {
            Write-Host "Skipping malformed calendar permission entry '$entry' for room $Identity" -ForegroundColor Yellow
            continue
        }

        $user = $parts[0].Trim()
        $accessRights = @($parts[1] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        if ([string]::IsNullOrWhiteSpace($user) -or $accessRights.Count -eq 0) {
            Write-Host "Skipping malformed calendar permission entry '$entry' for room $Identity" -ForegroundColor Yellow
            continue
        }

        if ($user -in $existingPermissionsUsers) {
            Write-Host "User '$user' already has permissions on calendar folder for room $Identity. Updating permissions." -ForegroundColor Yellow
            Set-MailboxFolderPermission -Identity $folderIdentity -User $user -AccessRights $accessRights -ErrorAction Stop | Out-Null
        }
        else {
            Write-Host "Adding calendar folder permissions for user '$user' on room $Identity with access rights: $($accessRights -join ",")" -ForegroundColor Cyan
            Add-MailboxFolderPermission -Identity $folderIdentity -User $user -AccessRights $accessRights -ErrorAction Stop | Out-Null
        }
    }
}

if (-not (Test-Path -Path $CsvPath)) {
    throw "Input CSV '$CsvPath' was not found."
}

Connect-ExchangeOnline

$roomSettings = Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter

foreach ($room in $roomSettings) {
    $identity = if (-not [string]::IsNullOrWhiteSpace($room.PrimarySmtpAddress)) { $room.PrimarySmtpAddress } else { $room.Identity }

    try {
        Write-Host "Processing room: $identity" -ForegroundColor Cyan

        $mailboxParams = @{
            Identity            = $identity
            DisplayName         = $room.DisplayName
            GrantSendOnBehalfTo = (ConvertTo-StringArray $room.SendOnBehalfPermissions)
            ErrorAction         = "Stop"
        }
        Set-Mailbox @mailboxParams

        $calendarConfigParams = @{
            Identity              = $identity
            WorkingHoursStartTime = $room.WorkingHoursStartTime
            WorkingHoursEndTime   = $room.WorkingHoursEndTime
            WorkingHoursTimeZone  = $room.WorkingHoursTimeZone
            WorkDays              = (ConvertTo-StringArray $room.WorkDays)
            ErrorAction           = "Stop"
        }
        Set-MailboxCalendarConfiguration @calendarConfigParams

        $calendarProcessingParams = @{
            Identity                             = $identity
            AutomateProcessing                   = $room.AutomateProcessing
            AllowConflicts                       = (ConvertTo-BoolValue $room.AllowConflicts)
            BookingType                          = $room.BookingType
            BookingWindowInDays                  = (ConvertTo-IntValue $room.BookingWindowInDays)
            MaximumDurationInMinutes             = (ConvertTo-IntValue $room.MaximumDurationInMinutes)
            AllowRecurringMeetings               = (ConvertTo-BoolValue $room.AllowRecurringMeetings)
            EnforceCapacity                      = (ConvertTo-BoolValue $room.EnforceCapacity)
            EnforceSchedulingHorizon             = (ConvertTo-BoolValue $room.EnforceSchedulingHorizon)
            ScheduleOnlyDuringWorkHours          = (ConvertTo-BoolValue $room.ScheduleOnlyDuringWorkHours)
            ConflictPercentageAllowed            = (ConvertTo-IntValue $room.ConflictPercentageAllowed)
            MaximumConflictInstances             = (ConvertTo-IntValue $room.MaximumConflictInstances)
            ForwardRequestsToDelegates           = (ConvertTo-BoolValue $room.ForwardRequestsToDelegates)
            DeleteAttachments                    = (ConvertTo-BoolValue $room.DeleteAttachments)
            DeleteComments                       = (ConvertTo-BoolValue $room.DeleteComments)
            RemovePrivateProperty                = (ConvertTo-BoolValue $room.RemovePrivateProperty)
            DeleteSubject                        = (ConvertTo-BoolValue $room.DeleteSubject)
            AddOrganizerToSubject                = (ConvertTo-BoolValue $room.AddOrganizerToSubject)
            DeleteNonCalendarItems               = (ConvertTo-BoolValue $room.DeleteNonCalendarItems)
            TentativePendingApproval             = (ConvertTo-BoolValue $room.TentativePendingApproval)
            EnableResponseDetails                = (ConvertTo-BoolValue $room.EnableResponseDetails)
            OrganizerInfo                        = (ConvertTo-BoolValue $room.OrganizerInfo)
            ResourceDelegates                    = (ConvertTo-StringArray $room.ResourceDelegates)
            RequestOutOfPolicy                   = (ConvertTo-StringArray $room.RequestOutOfPolicy)
            AllRequestOutOfPolicy                = (ConvertTo-BoolValue $room.AllRequestOutOfPolicy)
            BookInPolicy                         = (ConvertTo-StringArray $room.BookInPolicy)
            AllBookInPolicy                      = (ConvertTo-BoolValue $room.AllBookInPolicy)
            RequestInPolicy                      = (ConvertTo-StringArray $room.RequestInPolicy)
            AllRequestInPolicy                   = (ConvertTo-BoolValue $room.AllRequestInPolicy)
            AddAdditionalResponse                = (ConvertTo-BoolValue $room.AddAdditionalResponse)
            AdditionalResponse                   = $room.AdditionalResponse
            RemoveOldMeetingMessages             = (ConvertTo-BoolValue $room.RemoveOldMeetingMessages)
            AddNewRequestsTentatively            = (ConvertTo-BoolValue $room.AddNewRequestsTentatively)
            ProcessExternalMeetingMessages       = (ConvertTo-BoolValue $room.ProcessExternalMeetingMessages)
            RemoveForwardedMeetingNotifications  = (ConvertTo-BoolValue $room.RemoveForwardedMeetingNotifications)
            RemoveCanceledMeetings               = (ConvertTo-BoolValue $room.RemoveCanceledMeetings)
            EnableAutoRelease                    = (ConvertTo-BoolValue $room.EnableAutoRelease)
            PostReservationMaxClaimTimeInMinutes = (ConvertTo-IntValue $room.PostReservationMaxClaimTimeInMinutes)
            ErrorAction                          = "SilentlyContinue"
        }
        Write-Host "Updating calendar processing settings for room: $identity" -ForegroundColor Yellow
        Set-CalendarProcessing @calendarProcessingParams

        write-Host "Updating permissions for room: $identity" -ForegroundColor Yellow
        Sync-FullAccessPermissions -Identity $identity -DesiredUsers (ConvertTo-StringArray $room.FullAccessPermissions)
        Write-Host "Updating Send As permissions for room: $identity" -ForegroundColor Yellow
        Sync-SendAsPermissions -Identity $identity -DesiredTrustees (ConvertTo-StringArray $room.SendAsPermissions)
        Write-Host "Updating Calendar Folder permissions for room: $identity" -ForegroundColor Yellow
        Sync-CalendarFolderPermissions -Identity $identity -DesiredPermissions (ConvertTo-StringArray $room.CalendarFolderPermissions)

        Write-Host "Successfully updated room: $identity" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to update room: $identity. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
