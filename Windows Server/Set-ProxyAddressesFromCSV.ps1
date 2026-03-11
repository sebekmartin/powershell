param (
    [Parameter(Mandatory = $true)] [string]$CsvPath,
    [Parameter(Mandatory = $false)] [validateSet("UPN", "FirstAlias")] [string]$PrimaryAddress = "UPN",  # Default primary address type
    [Parameter(Mandatory = $false)] [string] $M365Subdomain
)

# Ensure the file exists
if (-Not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found at path: $CsvPath"
    return
}

# Import the Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Successfully imported Active Directory module" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import Active Directory module. Please ensure RSAT-AD-PowerShell feature is installed: $_"
    return
}

# Import the CSV data
$aliases = Import-Csv -Path $CsvPath
$validCsv = $true

# Validate the required columns
foreach ($alias in $aliases) {
    if (-Not ($alias.Alias -and $alias.UserPrincipalName -and $alias.TargetType)) {
        Write-Error "One or more required columns (Alias, UserPrincipalName, TargetType) are missing in the CSV file"
        $validCsv = $false
        break
    }
}

if (-Not $validCsv) {
    Write-Error "CSV file validation failed. Please check the required columns: Alias, UserPrincipalName, TargetType"
    return
}

# Group aliases by UserPrincipalName for users only
$userAliases = $aliases | Where-Object { $_.TargetType -eq "User" } | Group-Object -Property UserPrincipalName

Write-Host "Found $($userAliases.Count) users to process" -ForegroundColor Cyan

# Process each user
foreach ($userGroup in $userAliases) {
    $userPrincipalName = $userGroup.Name
    $userAliasesArray = $userGroup.Group
    
    Write-Host "Processing user: $userPrincipalName" -ForegroundColor Yellow
    
    try {
        # Get the user from Active Directory
        $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" -Properties ProxyAddresses -ErrorAction Stop
        
        if (-not $user) {
            Write-Host "WARNING: User not found: $userPrincipalName" -ForegroundColor Yellow
            continue
        }
        
        # Create the proxy addresses array
        $proxyAddresses = @()
        
        switch ($PrimaryAddress) {
            "UPN" {
                # 1. Add primary SMTP address (uppercase SMTP indicates primary)
                $proxyAddresses += "SMTP:$($user.UserPrincipalName)"
                
                
            }
            "FirstAlias" {
                # 1. Add first alias as primary
                if ($userAliasesArray.Count -gt 0) {
                    $firstAlias = $userAliasesArray[0].Alias
                    $proxyAddresses += "SMTP:$firstAlias"
                    $userAliasesArray = $userAliasesArray[1..($userAliasesArray.Count - 1)]
                }
            }
        }
        
        # 2. Add M365 domain address (smtp lowercase for secondary)
        if ($M365Subdomain) {
            $m365Address = $user.UserPrincipalName -replace "@.*", "@$M365Subdomain"
            $proxyAddresses += "smtp:$m365Address"
        }

        
        # 3. Add all aliases from CSV as secondary smtp addresses
        foreach ($aliasEntry in $userAliasesArray) {
            $aliasAddress = $aliasEntry.Alias
            # Only add if it's not already the primary address
            if ($aliasAddress -ne $user.UserPrincipalName) {
                $proxyAddresses += "smtp:$aliasAddress"
            }
        }
        
        # Remove duplicates while preserving order and convert to string array
        $proxyAddresses = $proxyAddresses | Select-Object -Unique
        $proxyAddressesArray = [string[]]$proxyAddresses
        
        # Update the user's proxy addresses in Active Directory
        Set-ADUser -Identity $user.DistinguishedName -Replace @{ProxyAddresses = $proxyAddressesArray } -ErrorAction Stop
        
        Write-Host "SUCCESS: Updated proxy addresses for $userPrincipalName" -ForegroundColor Green
        Write-Host "  Primary: $($proxyAddresses[0])" -ForegroundColor Gray
        if ($proxyAddresses.Count -gt 1) {
            Write-Host "  Secondary addresses: $($proxyAddresses[1..($proxyAddresses.Count-1)] -join ', ')" -ForegroundColor Gray
        }
        Write-Host ""
        
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Host "WARNING: User not found in Active Directory: $userPrincipalName" -ForegroundColor Yellow
    }
    catch {
        Write-Host "ERROR: Failed to update user $userPrincipalName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Script execution completed." -ForegroundColor Green
Write-Host "Summary: Processed $($userAliases.Count) users from CSV file." -ForegroundColor Cyan
