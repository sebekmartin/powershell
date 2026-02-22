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

# Process each domain and collect resolution results.
foreach ($row in $rows) {
    $domainRaw = [string]$row.$domainColumn
    $domain = $domainRaw.Trim()

    if ([string]::IsNullOrWhiteSpace($domain)) {
        $entry = [ordered]@{
            domain      = $domainRaw
            finalHost   = $null
            finalUrl    = $null
            publicIPs   = $null
            resolved    = $false
            error       = 'Domain value is empty.'
        }

        if ($validationIpNormalized) {
            $entry.match = $false
        }

        $results.Add([PSCustomObject]$entry)
        continue
    }

    $candidateUrls = @()
    if ($domain -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        $candidateUrls += $domain
    }
    else {
        $candidateUrls += "https://$domain"
        $candidateUrls += "http://$domain"
    }

    $finalUri = $null
    $requestError = $null

    # Resolve final URL by following redirects (HEAD first, then GET fallback).
    foreach ($url in $candidateUrls) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Method = 'HEAD'
            $request.AllowAutoRedirect = $true
            $request.MaximumAutomaticRedirections = 15
            $request.Timeout = 15000
            $request.ReadWriteTimeout = 15000
            $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DomainResolver/1.0'

            $response = $request.GetResponse()
            try {
                $finalUri = $response.ResponseUri
            }
            finally {
                $response.Close()
            }

            if ($finalUri) {
                break
            }
        }
        catch {
            $requestError = $_.Exception.Message

            if ($_.Exception.Response -and $_.Exception.Response.ResponseUri) {
                $finalUri = $_.Exception.Response.ResponseUri
                if ($finalUri) {
                    break
                }
            }

            try {
                $fallbackRequest = [System.Net.HttpWebRequest]::Create($url)
                $fallbackRequest.Method = 'GET'
                $fallbackRequest.AllowAutoRedirect = $true
                $fallbackRequest.MaximumAutomaticRedirections = 15
                $fallbackRequest.Timeout = 15000
                $fallbackRequest.ReadWriteTimeout = 15000
                $fallbackRequest.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DomainResolver/1.0'

                $fallbackResponse = $fallbackRequest.GetResponse()
                try {
                    $finalUri = $fallbackResponse.ResponseUri
                }
                finally {
                    $fallbackResponse.Close()
                }

                if ($finalUri) {
                    break
                }
            }
            catch {
                $requestError = $_.Exception.Message
                if ($_.Exception.Response -and $_.Exception.Response.ResponseUri) {
                    $finalUri = $_.Exception.Response.ResponseUri
                    if ($finalUri) {
                        break
                    }
                }
            }
        }
    }

    $hostToResolve = $domain
    if ($hostToResolve -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        try {
            $hostToResolve = ([System.Uri]$hostToResolve).Host
        }
        catch {
            $hostToResolve = $domain
        }
    }

    if ($finalUri -and $finalUri.Host) {
        $hostToResolve = $finalUri.Host
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
        elseif ($requestError) {
            $errorMessage = $requestError
        }
        else {
            $errorMessage = 'No public IP address found.'
        }
    }

    $entry = [ordered]@{
        domain      = $domain
        finalHost   = $hostToResolve
        finalUrl    = if ($finalUri) { $finalUri.AbsoluteUri } else { $null }
        publicIPs   = $publicIpValue
        resolved    = [bool]$publicIpValue
        error       = $errorMessage
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
