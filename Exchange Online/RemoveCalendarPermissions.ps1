# Set user name(s) which you want to remove from permissions of 
# Format this variable as a array of strings
# Use UserPrincipalName as identification of users in this variable
$usersToRemove;

# Remove all individual calendar permissions set for users which are in the usersToRemove list
# from calendars of all users in Microsoft 365 tenant.
foreach ($user in Get-EXOMailbox -RecipientTypeDetails UserMailbox) {
    $calendar = Get-EXOMailboxFolderStatistics -Identity $user.UserPrincipalName -FolderScope calendar | Where-Object { $_.FolderType -eq "Calendar" }
    foreach ($toRemove in $usersToRemove) {
        Remove-MailboxFolderPermission -Identity $calendar -User $toRemove -Confirm:$true
    }
}