# Loop through each user in the CSV
param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

Connect-ExchangeOnline

# Import the CSV file
$users = Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding UTF8

# Loop through each user in the CSV
foreach ($user in $users) {
    # Get the user's UserPrincipalName and Alias from CSV
    $userPrincipalName = $user.UserPrincipalName
    $alias = $user.Alias

    try {
        # Add the alias to the user
        Set-Mailbox -Identity $userPrincipalName -EmailAddresses @{add = $alias } -ErrorAction Stop

        Write-Host "SUCCESS: Alias $alias added to $userPrincipalName" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to add alias $alias to $userPrincipalName - Reason: $($_.Exception.Message)" -ForegroundColor Red
    }
}
