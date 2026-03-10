# The CSV is expected to have the following headers:
# WindowsEmailAddress, New_DisplayName, New_WindowsEmailAddress

param (
    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)

Connect-ExchangeOnline

$csv = Import-Csv -Path $CsvFilePath -Delimiter $CsvDelimiter -Encoding UTF8

# For each entry in the CSV, update the display name and UPN of the distribution group
foreach ($entry in $csv) {
    $WindowsEmailAddress = $entry.WindowsEmailAddress
    $newDisplayName = $entry.New_DisplayName
    $New_WindowsEmailAddress = $entry.New_WindowsEmailAddress

    Write-Host "Updating Contact: $WindowsEmailAddress" -ForegroundColor Cyan
    try {
        # Get the contact to check if it exists
        $contact = Get-Contact -Identity $WindowsEmailAddress -ErrorAction Stop

        # Update the contact with the new display name and UPN
        Set-Contact -Identity $WindowsEmailAddress -DisplayName $newDisplayName -WindowsEmailAddress $New_WindowsEmailAddress -ErrorAction Stop
        Write-Host "Successfully updated contact: $WindowsEmailAddress" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to update contact: $WindowsEmailAddress. $_" -ForegroundColor Red
    }
}
