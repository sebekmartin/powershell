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
    
    # Ask user, if he want to filter the users, which are modified?
    Write-Host "If you want, you can set the string to filter the users, you will modify. `n You can check the docs here: https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox?view=exchange-ps `n Please type the filter below." -BackgroundColor black -foregroundColor Cyan;
    $filter = Read-Host "Type in your filter [Default: *]"
    if ([string]::IsNullOrEmpty($filter)) {
        $filter = "RecipientType -eq UserMailbox";

        # Confirm, if user really want to set alias to all the users
        $confirmation = Read-Host "All users will now have alias with domain @$selectedDomain! Please confirm your choice [Y/N]";
    } else {
        $confirmation = Read-Host "All filtered users will now have alias with domain @$selectedDomain! Please confirm your choice [Y/N]";
    }

    
    
    # Check confirmation
    if ($confirmation -like "N") { Write-Host "You have declined. Terminating operation. No attributes were changed" -BackgroundColor black -foregroundColor red; return 0; }

    
    foreach ($user in Get-ExoMailbox -RecipientTypeDetails UserMailbox -Filter "$filter") {
        try {
            Set-Mailbox $user.alias -EmailAddresses @{add = $user.alias + "@" + $selectedDomain } -ErrorAction Stop
            Write-Host "Finished: $($user.DisplayName)" -BackgroundColor black -foregroundColor green;
        }
        catch {
            Write-Host "Error while setting up $($user.alias): `n$($error.Exception.message)" -ForegroundColor Red -BackgroundColor black;
            $error.clear();
        }
    }
}