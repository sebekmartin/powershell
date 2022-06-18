# Enviroment settings
# Variable for mailbox types you want to setup
$mailboxTypes = @();

# Ask user to input mailbox type identificators which he want to set up
Write-Output "Please select, which mailbox type(s) you want to set. `nPossibilities are: `n  ID   Description `n  a)   User Mailbox `n  b)   Room Mailbox `n  c)   Equipment Mailbox `nYou can also use combination of those possibilities. `nFor example: 'ac' is valid input"
$userSelection = Read-Host "Put in selected mailbox type identificators"

# Resolve user's input
switch ($userSelection) {
    {$_.contains("a")} {$mailboxTypes += "UserMailbox"}
    {$_.contains("b")} {$mailboxTypes += "RoomMailbox"}
    {$_.contains("c")} {$mailboxTypes += "EquipmentMailbox"}
    {$_.contains("d")} {$mailboxTypes += "SharedMailbox"}
    default {Write-Host "You have not selected a mailbox type. Terminating script..." -ForegroundColor Yellow -BackgroundColor Black; exit}
}


# Assign the default organization policy to the mailboxes
foreach ($user in Get-EXOMailbox -RecipientTypeDetails $mailboxTypes) {
    $calendar = Get-EXOMailboxFolderStatistics -Identity $user.UserPrincipalName -FolderScope calendar | Where-Object { $_.FolderType -eq "Calendar"}
    $folder = $user.UserPrincipalName + ":\" + $calendar.Name
    try {
        Set-MailboxFolderPermission -Identity $folder -User Default -AccessRights LimitedDetails -ErrorAction Stop -wa 0
        Write-Host "Finished successfully: $folder" -BackgroundColor black -foregroundColor green;
    } catch {
        Write-Host "Error while setting up $folder\: $($error.Exception.message)" -ForegroundColor Red -BackgroundColor black;
    }
}
