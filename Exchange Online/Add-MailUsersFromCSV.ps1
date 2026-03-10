# Import required modules
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Connect-ExchangeOnline

# Define CSV file path
param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

# Check if CSV file exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found at: $CsvPath"
    exit
}

# Import CSV data
$users = Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding UTF8

# Create mail users from CSV
foreach ($user in $users) {
    try {
        Write-Host "Creating mail user for: $($user.DisplayName)" -ForegroundColor Green
        
        New-MailUser -Name $user.DisplayName `
            -DisplayName $user.DisplayName `
            -ExternalEmailAddress $user.ExternalEmailAddress `
            -FirstName $user.FirstName `
            -LastName $user.LastName `
            -MicrosoftOnlineServicesID $user.UserPrincipalName `
            -Password (ConvertTo-SecureString $user.Password -AsPlainText -Force)
        
        Write-Host "Successfully created mail user: $($user.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create mail user for $($user.DisplayName): $($_.Exception.Message)"
    }
}

Write-Host "Mail user creation process completed." -ForegroundColor Yellow
