########################################
# VARIABLES
########################################
# USER DEFINED VARIABLES, PLEASE FILL THOSE IN BEFORE RUNNING THE SCRIPT!

# SMTP server
# 
# 
$SMTPserver = ""

# SMTP Port
# 
# 
$SMTPport = ""

# Credentials
#
#
$Credentials = ""

# SSL
# Do you want to use SSL during connection to SMTP server?
# Set this variable to $true or $false
$UseSsl = $true

# Email Sender
# In this variable, you define, who is the sender of email
# For pretty sender, use this format: 'DisplayName <email@domain.com>'
# Example: "John Smith <John@smith.com>"
$Sender = ""

# Email Recipients
# In this variable, you can specify one or more recipients of the message
# Example: "a@domain.com"
# If you want more: "a@domain.com", "b@domain.com"
$EmailRecipients = ""

# Subject
# Please fill in the subject of email
# String
$Subject = ""

# Body
# In this variable, you can define the body of the email
# You can use here HTML formating or stay just with plain text
$Body = ""

# Please fill in here the username, which you want to check
# If you are using domain, fill in the domain name
# Example - DOMAIN\username
$CheckedUserName = ""

# Please fill the process name or with WildCard characters, which you want to check
# Example: "MonS*" or "Adobe"
$ProcessToCheck = ""

# Users
# This variable is used to store names of users, which has defined process running
# under their username.
$users =  @()


#######################################
# SCRIPT
#######################################

# initialize the $users variable
Get-Process $processToCheck -IncludeUserName | ForEach-Object {$users += $_.UserName}


if(!$users.contains($checkedUserName)) {
    Send-MailMessage -From $Sender -To $EmailRecipients -Subject $Subject -BodyAsHtml $Body -SmtpServer $SMTPserver -Port $SMTPport -UseSsl
}