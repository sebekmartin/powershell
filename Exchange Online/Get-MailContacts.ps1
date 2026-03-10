# Get all contacts and select specific properties
$contacts = Get-MailContact -ResultSize Unlimited

# Select only the desired properties
$contacts = $contacts | Select-Object Name, DisplayName, ExternalEmailAddress, Alias, HiddenFromAddressListsEnabled, RequireSenderAuthenticationEnabled, EmailAddresses

# Modify properties for CSV export
$contacts = $contacts | ForEach-Object {
    # Format email addresses to only include SMTP addresses 
    $_.EmailAddresses = @($_.EmailAddresses | Where-Object { $_ -like 'smtp:*' }) -join '~'
    
    # Return the modified object
    $_
}

# Export the contacts to a CSV file
$contacts | Export-Csv -Path ".\contacts.csv" -NoTypeInformation -Encoding UTF8