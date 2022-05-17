# Description
This is set of scripts used for Exchange Online in Microsoft365.

# Short scripts descriptions

### SetCalendarPermissions.ps1
This script is used to set default company sharing permissions for Exchange online mailboxes of persons, rooms and equipment. You can set which of those mailbox groups you want to use on the beggining of the script.

### RemoveCalendarPermissions.ps1
This script is used to remove individually set permissions for user calendars. For example, user A sets his calendar permissions for user B at "None". You can use this script to remove those individually set permissions for user B from all mailboxes in organization. As the result, user B will use Default permissions set on Organization level.

### SetAliasToAllUsers.ps1
With this script, you can easily add new alias to all users in organization. After running this script, you will be asked, which domain from accepted domains in your tenant you want to use. After choosing one of them, script will add alias with this domain to all users in your tenant.