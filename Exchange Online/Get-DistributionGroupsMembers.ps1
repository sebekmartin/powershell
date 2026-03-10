# Parameter help description
param(
    [Parameter(Mandatory = $true)]
    [string]
    $sourceCSVPath,
    [Parameter(Mandatory = $false)]
    [string]
    $CsvDelimiter = ",",
    [Parameter(Mandatory = $false)]
    [string]
    $destinationCSVPath = ".\distribution-groups-members.csv"
)

Connect-ExchangeOnline

# Import the source CSV file
$sourceData = Import-Csv -Path $sourceCSVPath -Delimiter $CsvDelimiter -Encoding UTF8

# Prepare an array to hold the results
$results = @()

# Loop through each distribution group in the source CSV
foreach ($entry in $sourceData) {
    try {
        $groupMembers = Get-DistributionGroupMember -Identity $entry.Name -ErrorAction SilentlyContinue
        if ($groupMembers) {
            foreach ($member in $groupMembers) {
                $results += [PSCustomObject]@{
                    group = $entry.Name
                    role  = "member"
                    email = $member.UserPrincipalName
                }
            }
        }
        else {
            Write-Host "No members found for group: $($entry.Name)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to get members for group: $($entry.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Export the results to the destination CSV file
$results | Export-Csv -Path $destinationCSVPath -NoTypeInformation -Encoding UTF8

## TODO: Add handling of users who do not have UserPrincipalName (e.g., contacts)
## TODO: Add handling for groups without email - security groups?

# $result = Foreach ($group in $distributionGroupNames) {$users = Get-DistributionGroupMember $group.Name | Where-Object {$_.RecipientType -eq "User"}; Foreach ($user in $Users) {$adUser = Get-ADUser -Filter * -Properties * | Where-Object {$_.DisplayName -like $user.Name}; Write-Host "Group: $($group.Name), member: $($adUser.UserPrincipalName)"}}