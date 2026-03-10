param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

Connect-ExchangeOnline

$csv = Import-Csv -Path $CsvFilePath -Delimiter $CsvDelimiter -Encoding UTF8

# For each entry in the CSV, create contact with the display name and UPN
foreach ($entry in $csv) {

    try {
        # Create contact
        $contact = New-MailContact -Name $entry.Name -Alias $entry.Alias -DisplayName $entry.DisplayName -ExternalEmailAddress $entry.ExternalEmailAddress -ErrorAction Stop

        $entry.ExternalEmailAddress = $entry.ExternalEmailAddress -replace "^SMTP:", ""
        $entry.HiddenFromAddressListsEnabled = $entry.HiddenFromAddressListsEnabled -in @("PRAVDA", "TRUE", "YES")
        $entry.RequireSenderAuthenticationEnabled = $entry.RequireSenderAuthenticationEnabled -in @("PRAVDA", "TRUE", "YES")

        # Update the contact with additional properties
        Set-MailContact -Identity $contact.Identity -HiddenFromAddressListsEnabled $entry.HiddenFromAddressListsEnabled -RequireSenderAuthenticationEnabled $entry.RequireSenderAuthenticationEnabled # -EmailAddresses ($entry.EmailAddresses.replace("~", ",") -split ",") -ErrorAction Stop
        Write-Host "Successfully created contact: $($entry.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to create contact: $($entry.DisplayName). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}