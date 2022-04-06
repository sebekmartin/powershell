# Enviroment settings
# Choose, which mailbox types you want to setup
# Set true, if you want to set permissions on this mailbox type, false if not
$setupUsers = $true;
$setupRooms = $true;
$setupEquipment = $true;
$mailboxTypes;

# Setup the mailboxTypes for filtering
if ($setupUsers) {$mailboxTypes += "UserMailbox"}
if ($setupRooms) {$mailboxTypes += "RoomMailbox"}
if ($setupEquipment) {$mailboxTypes += "EquipmentMailbox"}


# Assign the default organization policy to the mailboxes
foreach ($user in Get-EXOMailbox -RecipientTypeDetails $mailboxTypes) {
    $calendar = Get-EXOMailboxFolderStatistics -Identity $user.UserPrincipalName -FolderScope calendar | Where-Object { $_.FolderType -eq "Calendar" }
    Set-EXOMailboxFolderPermission -Identity $calendar -User Default -AccessRights LimitedDetails
}
