# Script to add users to distribution groups from CSV
# CSV should have columns: group, role, email

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

# Import the CSV file
$users = Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding UTF8

# Connect to Exchange Online (uncomment if needed)
Connect-ExchangeOnline

foreach ($user in $users) {
    try {
        # Add user as member to the distribution group
        Add-DistributionGroupMember -Identity $user.group -Member $user.email -ErrorAction Stop
        Write-Host "Added $($user.email) as member to $($user.group)" -ForegroundColor Green
        
        # If role is manager or owner, also add as owner
        if ($user.role -eq "manager" -or $user.role -eq "owner") {
            Set-DistributionGroup -Identity $user.group -ManagedBy @{Add = $user.email } -ErrorAction Stop
            Write-Host "Added $($user.email) as owner to $($user.group)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to process $($user.email) for group $($user.group): $($_.Exception.Message)"
    }
}

Write-Host "Script completed." -ForegroundColor Cyan