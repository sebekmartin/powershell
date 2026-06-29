Param(
    [Parameter(Mandatory = $True)]
    [String]
    $SharepointURL,
    [Parameter(Mandatory = $True)]
    [String]
    $tenantID,
    [Parameter(Mandatory = $false)]
    [string]
    $CsvPath,
    [Parameter(Mandatory = $false)]
    [string]
    $CsvDelimiter = ","
)

Connect-SPOService -Url $SharepointURL;

$list = @() #list of UPN to pass to the SP command
$Totalusers = 0 #total user provisioned.

# Build list of UPNs either from CSV or from licensed users in Entra ID.
$userUpns = @()

if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
    if (-not (Test-Path -Path $CsvPath)) {
        Write-Error "CSV file not found at path: $CsvPath"
        exit
    }

    $csvRows = @(Import-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding UTF8)
    if ($csvRows.Count -eq 0) {
        Write-Error "CSV file '$CsvPath' does not contain any data rows."
        exit
    }

    $upnColumnName = $csvRows[0].PSObject.Properties.Name | Select-Object -First 1
    $userUpns = @(
        foreach ($row in $csvRows) {
            $upn = [string]$row.$upnColumnName
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $upn.Trim()
            }
        }
    )
}
else {
    $scope = 'User.Read.All'
    Connect-MgGraph -TenantId $tenantId -Scopes $scope

    # Get licensed users
    $users = Get-MgUser -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedUserCount -All -Select UserPrincipalName
    $userUpns = @(
        foreach ($u in $users) {
            if (-not [string]::IsNullOrWhiteSpace($u.UserPrincipalName)) {
                $u.UserPrincipalName.Trim()
            }
        }
    )

    Disconnect-MgGraph
}

foreach ($upn in $userUpns) {
    $Totalusers++
    Write-Host "$Totalusers/$($userUpns.Count) - Processing user: $upn" -ForegroundColor Cyan
    $list += $upn

    if ($list.Count -eq 199) {
        #We reached the limit
        Write-Host "Batch limit reached, requesting provision for the current batch" -ForegroundColor Yellow
        Request-SPOPersonalSite -UserEmails $list -NoWait
        Start-Sleep -Milliseconds 655
        $list = @()
    }
}

if ($list.Count -gt 0) {
    Request-SPOPersonalSite -UserEmails $list -NoWait
}
Disconnect-SPOService
Write-Host "Completed OneDrive Provisioning for $Totalusers users"