# The CSV is expected to have the following headers:
# PrimarySmtpAddress, New_DisplayName, New_PrimarySmtpAddress

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
    $primarySmtpAddress = $entry.PrimarySmtpAddress
    $newDisplayName = $entry.New_DisplayName
    $New_PrimarySmtpAddress = $entry.New_PrimarySmtpAddress

    Write-Host "Updating Distribution Group: $primarySmtpAddress" -ForegroundColor Cyan
    try {
        # Get the distribution group to check if it exists
        $group = Get-DistributionGroup -Identity $primarySmtpAddress -ErrorAction Stop

        # Update the distribution group
        Set-DistributionGroup -Identity $primarySmtpAddress -DisplayName $newDisplayName -PrimarySmtpAddress $New_PrimarySmtpAddress -ErrorAction Stop
        Write-Host "Successfully updated Distribution Group: $primarySmtpAddress" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to update Distribution Group: $primarySmtpAddress. $_" -ForegroundColor Red
    }
}
