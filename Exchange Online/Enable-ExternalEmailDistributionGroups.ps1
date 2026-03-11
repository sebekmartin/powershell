# Connect to Exchange Online
Connect-ExchangeOnline

# Get all distribution groups and enable external email delivery
Get-DistributionGroup | ForEach-Object {
    Write-Host "Enabling external email for: $($_.DisplayName)"
    Set-DistributionGroup -Identity $_.Identity -RequireSenderAuthenticationEnabled $false
}

Write-Host "External email delivery enabled for all distribution groups."