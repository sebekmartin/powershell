# Fill here the email address of the user who you want to add into all groups.
$memberEmail = ""

# Get user object from azure based on the email address.
$newUser = Get-AzureADUser -ObjectId $memberEmail

# In this cycle, for every security group (which is defined by parameters, that is security enabled and mail disabled)
# get objectID of this group and add new member to this group.
# At the end, print the group name.
foreach ($group in (Get-AzureADGroup -All $true | where-object { $_.MailEnabled -eq $false -and $_.SecurityEnabled -eq $true})) {
    Add-AzureADGroupMember -ObjectId $group.ObjectId -RefObjectId $newUser.ObjectId
    Write-Output $group.DisplayName 
}