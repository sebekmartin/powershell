param([Parameter(Mandatory = $false)]
    [string]
    $destinationCSVPath = ".\distribution-groups.csv"
)

Connect-ExchangeOnline

# Get all distribution groups and select specific properties
$distributionGroups = Get-DistributionGroup -ResultSize Unlimited 

# Select only the desired properties
$distributionGroups = $distributionGroups | Select-Object Name, PrimarySmtpAddress, Alias, GroupType, HiddenFromAddressListsEnabled, MemberJoinRestriction, MemberDepartRestriction, RequireSenderAuthenticationEnabled, EmailAddresses, Managedby 


# Modify properties for CSV export
$distributionGroups = $distributionGroups | ForEach-Object {
    # Resolve owners of the distribution groups
    $_.Managedby = @($_.Managedby | ForEach-Object { (Get-User -Identity $_).UserPrincipalName }) -join '~'
    
    # Format email addresses to only include SMTP addresses 
    $_.EmailAddresses = @($_.EmailAddresses | Where-Object { $_ -like 'smtp:*' }) -join '~'
    
    # Change GroupType to Exchange Online format
    if ($_.GroupType -like "*Security*") {
        $_.GroupType = "Security"
    }
    else {
        $_.GroupType = "Distribution"
    }
    
    # Return the modified object
    $_
}

# Export the distribution groups to a CSV file
$distributionGroups | Export-Csv -Path $destinationCSVPath -NoTypeInformation -Encoding UTF8