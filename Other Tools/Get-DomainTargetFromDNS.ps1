[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$validationIP,

    [Parameter(Mandatory = $true)]
    [string]$sourceCSV,

    [Parameter(Mandatory = $true)]
    [string]$outputFile,

    [Parameter(Mandatory = $true)]
    [string]$csvDelimiter
)

# Validate basic inputs.
if (-not (Test-Path -Path $sourceCSV)) {
    throw "Source CSV file '$sourceCSV' was not found."
}

$validationIpNormalized = $null
# Normalize and validate validation IP only when provided.
if (-not [string]::IsNullOrWhiteSpace($validationIP)) {
    $parsedValidationIp = $null
    if (-not [System.Net.IPAddress]::TryParse($validationIP.Trim(), [ref]$parsedValidationIp)) {
        throw "Parameter validationIP '$validationIP' is not a valid IP address."
    }
    $validationIpNormalized = $parsedValidationIp.ToString()
}

# Load input rows from CSV.
$rows = Import-Csv -Path $sourceCSV -Delimiter $csvDelimiter -Encoding UTF8
if (-not $rows) {
    throw "Source CSV '$sourceCSV' does not contain any data rows."
}

$columnNames = $rows[0].PSObject.Properties.Name
if (-not $columnNames -or $columnNames.Count -eq 0) {
    throw "Source CSV '$sourceCSV' does not contain any columns."
}

# Try to auto-detect the most likely domain column.
$preferredColumns = @('domain', 'Domain', 'DOMAIN', 'hostname', 'HostName', 'host', 'Host', 'url', 'Url', 'URL', 'name', 'Name')
$domainColumn = $null
foreach ($candidate in $preferredColumns) {
    if ($columnNames -contains $candidate) {
        $domainColumn = $candidate
        break
    }
}
if (-not $domainColumn) {
    $domainColumn = $columnNames[0]
}

Write-Host "Using CSV domain column: $domainColumn" -ForegroundColor Cyan

$results = New-Object System.Collections.Generic.List[object]

# Process each domain and collect DNS-based resolution results.
foreach ($row in $rows) {
    $domainRaw = [string]$row.$domainColumn
    $domain = $domainRaw.Trim()

    if ([string]::IsNullOrWhiteSpace($domain)) {
        $entry = [ordered]@{
            domain    = $domainRaw
            dnsHost   = $null
            publicIPs = $null
            resolved  = $false
            error     = 'Domain value is empty.'
        }

        if ($validationIpNormalized) {
            $entry.match = $false
        }

        $results.Add([PSCustomObject]$entry)
        continue
    }

    # Accept URL-like values in CSV and resolve only the hostname part.
    $hostToResolve = $domain
    if ($domain -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        try {
            $hostToResolve = ([System.Uri]$domain).Host
        }
        catch {
            $hostToResolve = $domain
        }
    }

    $resolvedPublicIps = New-Object System.Collections.Generic.List[string]
    $dnsError = $null

    # Resolve DNS and keep only public addresses.
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($hostToResolve)

        foreach ($address in $addresses) {
            $ipString = $address.ToString()
            $isPublic = $true

            if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                $octets = $ipString.Split('.')
                if ($octets.Count -eq 4) {
                    $o1 = [int]$octets[0]
                    $o2 = [int]$octets[1]

                    if ($o1 -eq 10) { $isPublic = $false }
                    elseif ($o1 -eq 127) { $isPublic = $false }
                    elseif ($o1 -eq 0) { $isPublic = $false }
                    elseif ($o1 -eq 169 -and $o2 -eq 254) { $isPublic = $false }
                    elseif ($o1 -eq 172 -and $o2 -ge 16 -and $o2 -le 31) { $isPublic = $false }
                    elseif ($o1 -eq 192 -and $o2 -eq 168) { $isPublic = $false }
                    elseif ($o1 -eq 100 -and $o2 -ge 64 -and $o2 -le 127) { $isPublic = $false }
                    elseif ($o1 -ge 224) { $isPublic = $false }
                }
            }
            elseif ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                if ($address.IsIPv6LinkLocal -or $address.IsIPv6Multicast -or $address.IsIPv6SiteLocal -or $address.IsIPv6Teredo) {
                    $isPublic = $false
                }
                elseif ($address.Equals([System.Net.IPAddress]::IPv6Loopback)) {
                    $isPublic = $false
                }
                elseif ($ipString.StartsWith('fc', [System.StringComparison]::OrdinalIgnoreCase) -or $ipString.StartsWith('fd', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isPublic = $false
                }
                elseif ($ipString.StartsWith('fe80', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isPublic = $false
                }
            }
            else {
                $isPublic = $false
            }

            if ($isPublic -and -not $resolvedPublicIps.Contains($ipString)) {
                $resolvedPublicIps.Add($ipString)
            }
        }
    }
    catch {
        $dnsError = $_.Exception.Message
    }

    $publicIpValue = $null
    if ($resolvedPublicIps.Count -gt 0) {
        $publicIpValue = ($resolvedPublicIps | Sort-Object) -join '|'
    }

    $errorMessage = $null
    if (-not $publicIpValue) {
        if ($dnsError) {
            $errorMessage = $dnsError
        }
        else {
            $errorMessage = 'No public IP address found.'
        }
    }

    $entry = [ordered]@{
        domain    = $domain
        dnsHost   = $hostToResolve
        publicIPs = $publicIpValue
        resolved  = [bool]$publicIpValue
        error     = $errorMessage
    }

    # Add optional validation result when validationIP is supplied.
    if ($validationIpNormalized) {
        $isMatch = $false
        if ($publicIpValue) {
            foreach ($ip in $resolvedPublicIps) {
                if ($ip -eq $validationIpNormalized) {
                    $isMatch = $true
                    break
                }
            }
        }
        $entry.match = $isMatch
    }

    $results.Add([PSCustomObject]$entry)
}

# Write final CSV output.
$results | Export-Csv -Path $outputFile -Delimiter $csvDelimiter -NoTypeInformation -Encoding UTF8

Write-Host "Done. Output written to: $outputFile" -ForegroundColor Green
