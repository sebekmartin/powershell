param([Parameter(Mandatory = $false)]
    [string]
    $destinationCSVPath = ".\equipment-settings.csv"
)

Connect-ExchangeOnline

# Load all Equipment mailboxes
$equipments = Get-Mailbox -RecipientTypeDetails EquipmentMailbox -ResultSize Unlimited
$results = @()

foreach ($equipment in $equipments) {
    try {
        try {
            $equipmentMailbox = Get-Mailbox -Identity $equipment.Identity
            $calendarProcessing = Get-CalendarProcessing -Identity $equipment.Identity -ErrorAction SilentlyContinue
            $calendarConfiguration = Get-MailboxCalendarConfiguration -Identity $equipment.Identity -ErrorAction SilentlyContinue
            $mailboxPermissions = Get-MailboxPermission -Identity $equipment.Identity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where-Object { $_.IsInherited -eq $false -and $_.User.toString() -ne "NT AUTHORITY\SELF" }
            $calendarFolder = Get-EXOMailboxFolderStatistics -Identity $equipment.Identity -FolderScope calendar | Where-Object { $_.FolderType -eq "Calendar" }
            $calendarFolderPermissions = Get-MailboxFolderPermission -Identity "$($equipment.PrimarySmtpAddress):\$($calendarFolder.Name)" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where-Object { $_.IsInherited -eq $false -and $_.User.toString() -ne "NT AUTHORITY\SELF" }

            $recipientPermissions = Get-RecipientPermission -Identity $equipment.Identity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where-Object { $_.IsInherited -eq $false -and $_.Trustee.toString() -ne "NT AUTHORITY\SELF" }

            # Validate that required objects were retrieved
            if (-not $calendarProcessing -or -not $calendarConfiguration) {
                Write-Host "Skipping equipment $($equipment.Name) - unable to retrieve calendar settings" -ForegroundColor Yellow
                continue
            }
        }
        catch {
            Write-Host "Failed to retrieve settings for equipment: $($equipment.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
        }

        $output = [PSCustomObject]@{
            Name                                 = $equipment.Name
            Identity                             = $equipment.Identity
            DisplayName                          = $equipment.DisplayName
            PrimarySmtpAddress                   = $equipment.PrimarySmtpAddress
            WorkDays                             = if ($calendarConfiguration.WorkDays) { $calendarConfiguration.WorkDays -join "~" } else { "" }
            WorkingHoursStartTime                = $calendarConfiguration.WorkingHoursStartTime
            WorkingHoursEndTime                  = $calendarConfiguration.WorkingHoursEndTime
            WorkingHoursTimeZone                 = $calendarConfiguration.WorkingHoursTimeZone
            AutomateProcessing                   = $calendarProcessing.AutomateProcessing
            AllowConflicts                       = $calendarProcessing.AllowConflicts
            AllowDistributionGroup               = $calendarProcessing.AllowDistributionGroup
            AllowMultipleResources               = $calendarProcessing.AllowMultipleResources
            BookingType                          = $calendarProcessing.BookingType
            BookingWindowInDays                  = $calendarProcessing.BookingWindowInDays
            MaximumDurationInMinutes             = $calendarProcessing.MaximumDurationInMinutes
            AllowRecurringMeetings               = $calendarProcessing.AllowRecurringMeetings
            EnforceCapacity                      = $calendarProcessing.EnforceCapacity
            EnforceSchedulingHorizon             = $calendarProcessing.EnforceSchedulingHorizon
            ScheduleOnlyDuringWorkHours          = $calendarProcessing.ScheduleOnlyDuringWorkHours
            ConflictPercentageAllowed            = $calendarProcessing.ConflictPercentageAllowed
            MaximumConflictInstances             = $calendarProcessing.MaximumConflictInstances
            ForwardRequestsToDelegates           = $calendarProcessing.ForwardRequestsToDelegates
            DeleteAttachments                    = $calendarProcessing.DeleteAttachments
            DeleteComments                       = $calendarProcessing.DeleteComments
            RemovePrivateProperty                = $calendarProcessing.RemovePrivateProperty
            DeleteSubject                        = $calendarProcessing.DeleteSubject
            AddOrganizerToSubject                = $calendarProcessing.AddOrganizerToSubject
            DeleteNonCalendarItems               = $calendarProcessing.DeleteNonCalendarItems
            TentativePendingApproval             = $calendarProcessing.TentativePendingApproval
            EnableResponseDetails                = $calendarProcessing.EnableResponseDetails
            OrganizerInfo                        = $calendarProcessing.OrganizerInfo
            ResourceDelegates                    = if ($calendarProcessing.ResourceDelegates) { $calendarProcessing.ResourceDelegates -join "~" } else { "" }
            RequestOutOfPolicy                   = if ($calendarProcessing.RequestOutOfPolicy) { $calendarProcessing.RequestOutOfPolicy -join "~" } else { "" }
            AllRequestOutOfPolicy                = $calendarProcessing.AllRequestOutOfPolicy
            BookInPolicy                         = if ($calendarProcessing.BookInPolicy) { $calendarProcessing.BookInPolicy -join "~" } else { "" }
            AllBookInPolicy                      = $calendarProcessing.AllBookInPolicy
            RequestInPolicy                      = if ($calendarProcessing.RequestInPolicy) { $calendarProcessing.RequestInPolicy -join "~" } else { "" }
            AllRequestInPolicy                   = $calendarProcessing.AllRequestInPolicy
            AddAdditionalResponse                = $calendarProcessing.AddAdditionalResponse
            AdditionalResponse                   = $calendarProcessing.AdditionalResponse
            RemoveOldMeetingMessages             = $calendarProcessing.RemoveOldMeetingMessages
            AddNewRequestsTentatively            = $calendarProcessing.AddNewRequestsTentatively
            ProcessExternalMeetingMessages       = $calendarProcessing.ProcessExternalMeetingMessages
            RemoveForwardedMeetingNotifications  = $calendarProcessing.RemoveForwardedMeetingNotifications
            RemoveCanceledMeetings               = $calendarProcessing.RemoveCanceledMeetings
            EnableAutoRelease                    = $calendarProcessing.EnableAutoRelease
            PostReservationMaxClaimTimeInMinutes = $calendarProcessing.PostReservationMaxClaimTimeInMinutes
            FullAccessPermissions                = if ($mailboxPermissions) { ($mailboxPermissions | ForEach-Object { $_.User.ToString() }) -join "~" } else { "" }
            SendAsPermissions                    = if ($recipientPermissions) { ($recipientPermissions | ForEach-Object { $_.Trustee.ToString() }) -join "~" } else { "" }
            SendOnBehalfPermissions              = if ($equipmentMailbox.GrantSendOnBehalfTo) { ($equipmentMailbox.GrantSendOnBehalfTo | ForEach-Object { $_.PrimarySmtpAddress.ToString() }) -join "~" } else { "" }
            CalendarFolderPermissions            = if ($calendarFolderPermissions) { ($calendarFolderPermissions | ForEach-Object { "$($_.User):$($_.AccessRights)" }) -join "~" } else { "" }
        }
        $results += $output
        Write-Host "Successfully retrieved settings for equipment: $($equipment.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to update settings for equipment: $($equipment.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$results | Export-Csv -Path $destinationCSVPath -NoTypeInformation -Encoding UTF8