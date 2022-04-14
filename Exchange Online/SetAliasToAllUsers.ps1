# Variables needed for the script to run correctly
$i = 0;
$details = Get-AzureADTenantDetail;
$domains = @();


Write-Host "These are your available domains:" -BackgroundColor black -foregroundColor Cyan;
Write-Output("#####################################")

# Load domain information from the Tenant details
$details.VerifiedDomains | ForEach-Object { $domains += $_.name; Write-Output("[$i] $($_.name)"); $i++ };
Write-Output("#####################################")

# Check if there is domain available to be assigned as an alias
if ($domains.length -eq 1) {
    Write-Host "You have only one domain available, so you already have all users set up with that domain." -BackgroundColor Black -ForegroundColor green;
    return 0;
}
else {
    # Ask user to select domain, which they want to set up as alias.
    $userSelection = Read-Host "Please choose one of your domains and write here its number"
    $selectedDomain = $domains[$userSelection];
    
    # Confirm, if user really want to set alias to all the users
    $confirmation = Read-Host "All users will now have alias with domain @$selectedDomain! Please confirm your choice [Y/N]";
    
    # Check confirmation
    if ($confirmation -like "N") { Write-Host "You have declined. Terminating operation. No attributes were changed" -BackgroundColor black -foregroundColor red; return 0; }

    
    foreach ($user in Get-Mailbox -RecipientTypeDetails UserMailbox) {
        try {
            Set-Mailbox $user.alias -EmailAddresses @{add = $user.alias + "@" + $selectedDomain } -ErrorAction Stop
            Write-Host "Finished: $user" -BackgroundColor black -foregroundColor green;
        }
        catch {
            Write-Host "Error while setting up $($user.alias): `n$($error.Exception.message)" -ForegroundColor Red -BackgroundColor black;
            $error.clear();
        }
    }
    return 0;
}