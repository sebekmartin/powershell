param (
    [Parameter(Mandatory = $true)]
    [string]$csvFilePath
)

# Ensure the file exists
if (-Not (Test-Path $csvFilePath)) {
    Write-Error "CSV file not found at path: $csvFilePath"
    return
}

# Import the CSV data
$users = Import-Csv -Path $csvFilePath
$validCsv = $true

# Validate the required columns
foreach ($user in $users) {
    if (-Not ($user.FirstName -and $user.LastName -and $user.DisplayName -and $user.UserPrincipalName -and $user.Password -and $user.UsageLocation -and $user.MailNickname)) {
        Write-Error "One or more required columns are missing in the CSV file for user: $($user.DisplayName)"
        $validCsv = $false
        continue
    }
}
if (-Not $validCsv) {
    Write-Error "CSV file validation failed. Please check the required columns."
    return
}

# Connect to Entra ID (Azure AD)
Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome

# Loop through each user in the CSV file
foreach ($user in $users) {
    $PasswordProfile = @{
        Password                      = $user.Password
        ForceChangePasswordNextSignIn = $true
    }

    # Create a new user
    try {
        New-MgBetaUser -MailNickname $user.MailNickname -DisplayName $user.DisplayName -GivenName $user.FirstName -Surname $user.LastName -UserPrincipalName $user.UserPrincipalName -UsageLocation $user.UsageLocation -PasswordProfile $passwordProfile -AccountEnabled
        Write-Host "User $($user.UserPrincipalName) created successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create user $($user.UserPrincipalName): $_"
    }
}



