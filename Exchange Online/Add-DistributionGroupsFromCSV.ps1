# This script is designed to follow script called Get-DistributionGroups.ps1 from this repository.
param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ","
)


# Connect to Exchange Online
Connect-ExchangeOnline

# Import CSV file
$groups = Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding UTF8

# Create distribution groups from CSV
foreach ($group in $groups) {
    try {
        $new_group = $null
        # Create new distribution group
        if (Get-DistributionGroup -Identity $group.Name) {
            Write-Host "Distribution group $($group.Name) already exists. Using existing group..." -ForegroundColor Yellow
            $new_group = Get-DistributionGroup -Identity $group.Name
        }
        else {
            $new_group = New-DistributionGroup -Name $group.Name -PrimarySmtpAddress $group.PrimarySmtpAddress -Type $group.GroupType -DisplayName $group.Name 
        }
        $group.HiddenFromAddressListsEnabled = $group.HiddenFromAddressListsEnabled -in @("PRAVDA", "TRUE", "YES")
        $group.RequireSenderAuthenticationEnabled = $group.RequireSenderAuthenticationEnabled -in @("PRAVDA", "TRUE", "YES")

        # Set additional properties to the distribution group
        Set-DistributionGroup -Identity $new_group.Identity -HiddenFromAddressListsEnabled $group.HiddenFromAddressListsEnabled -MemberJoinRestriction $group.MemberJoinRestriction -MemberDepartRestriction $group.MemberDepartRestriction -RequireSenderAuthenticationEnabled $group.RequireSenderAuthenticationEnabled  -EmailAddresses ($group.EmailAddresses.replace("~", ",") -split ",")
        
        # Set manager of the group if specified
        if ($group.Managedby -ne "") {
            Set-DistributionGroup -Identity $new_group.Identity -ManagedBy $group.Managedby.replace("~", ",")
        }

        Write-Host "Successfully created distribution group: $($group.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create distribution group: $($group.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false