[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFolder,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CheckFolder,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvOutputPath,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeRelativePathPrefix = @()
)

function Get-NormalizedRelativePaths {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseFolder,

        [Parameter(Mandatory = $true)]
        [ValidateSet('File', 'Directory')]
        [string]$ItemType
    )

    $resolvedBaseFolder = (Resolve-Path -Path $BaseFolder).Path
    $baseFolderUri = New-Object System.Uri(($resolvedBaseFolder.TrimEnd('\') + '\'))

    $childItems = if ($ItemType -eq 'File') {
        Get-ChildItem -Path $resolvedBaseFolder -File -Recurse
    }
    else {
        Get-ChildItem -Path $resolvedBaseFolder -Directory -Recurse
    }

    $childItems | ForEach-Object {
        $itemUri = New-Object System.Uri($_.FullName)
        $relativePath = $baseFolderUri.MakeRelativeUri($itemUri).ToString()
        [System.Uri]::UnescapeDataString($relativePath).Replace('\', '/')
    }
}

function Get-NormalizedRelativePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseFolder,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $baseFolderUri = New-Object System.Uri(($BaseFolder.TrimEnd('\') + '\'))
    $fileUri = New-Object System.Uri($FilePath)
    $relativePath = $baseFolderUri.MakeRelativeUri($fileUri).ToString()
    [System.Uri]::UnescapeDataString($relativePath).Replace('\', '/')
}

function Get-NormalizedPrefix {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $Prefix.Replace('\', '/').Trim('/')
}

function Test-IsExcludedRelativePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [AllowEmptyCollection()]
        [string[]]$ExcludedPrefixes = @()
    )

    $normalizedPath = $RelativePath.Replace('\', '/').Trim('/')

    foreach ($prefix in $ExcludedPrefixes) {
        if (
            $normalizedPath.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalizedPath.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            return $true
        }
    }

    return $false
}

if (-not (Test-Path -Path $SourceFolder -PathType Container)) {
    Write-Error "Source folder does not exist or is not a directory: $SourceFolder"
    exit 1
}

if (-not (Test-Path -Path $CheckFolder -PathType Container)) {
    Write-Error "Check folder does not exist or is not a directory: $CheckFolder"
    exit 1
}

$csvOutputPathResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvOutputPath)
$csvDirectory = Split-Path -Path $csvOutputPathResolved -Parent
if ($csvDirectory -and -not (Test-Path -Path $csvDirectory -PathType Container)) {
    New-Item -Path $csvDirectory -ItemType Directory -Force | Out-Null
}

$excludedPrefixes = [System.Collections.Generic.List[string]]::new()
if ($ExcludeRelativePathPrefix.Count -gt 0) {
    foreach ($prefix in $ExcludeRelativePathPrefix) {
        if (-not [string]::IsNullOrWhiteSpace($prefix)) {
            $excludedPrefixes.Add((Get-NormalizedPrefix -Prefix $prefix))
        }
    }
}

$checkFilePaths = @(Get-NormalizedRelativePaths -BaseFolder $CheckFolder -ItemType File)
$checkDirectoryPaths = @(Get-NormalizedRelativePaths -BaseFolder $CheckFolder -ItemType Directory)
$checkFilePathSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$checkDirectoryPathSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($path in $checkFilePaths) {
    [void]$checkFilePathSet.Add($path)
}

foreach ($path in $checkDirectoryPaths) {
    [void]$checkDirectoryPathSet.Add($path)
}

$sourceFolderResolved = (Resolve-Path -Path $SourceFolder).Path
$csvWriter = $null
$missingItemCount = 0

try {
    $csvWriter = [System.IO.StreamWriter]::new($csvOutputPathResolved, $false, [System.Text.UTF8Encoding]::new($true))
    $csvWriter.WriteLine('"ItemType","RelativePath","ExistsInCheckFolder"')

    foreach ($sourceDirectory in Get-ChildItem -Path $sourceFolderResolved -Directory -Recurse) {
        $relativePath = Get-NormalizedRelativePath -BaseFolder $sourceFolderResolved -FilePath $sourceDirectory.FullName

        if (Test-IsExcludedRelativePath -RelativePath $relativePath -ExcludedPrefixes $excludedPrefixes) {
            continue
        }

        if (-not $checkDirectoryPathSet.Contains($relativePath)) {
            $escapedRelativePath = $relativePath.Replace('"', '""')
            $csvWriter.WriteLine("""Directory"",""$escapedRelativePath"",""False""")
            Write-Host "[Missing directory] $relativePath"
            $missingItemCount++
        }
    }

    foreach ($sourceFile in Get-ChildItem -Path $sourceFolderResolved -File -Recurse) {
        $relativePath = Get-NormalizedRelativePath -BaseFolder $sourceFolderResolved -FilePath $sourceFile.FullName

        if (Test-IsExcludedRelativePath -RelativePath $relativePath -ExcludedPrefixes $excludedPrefixes) {
            continue
        }

        if (-not $checkFilePathSet.Contains($relativePath)) {
            $escapedRelativePath = $relativePath.Replace('"', '""')
            $csvWriter.WriteLine("""File"",""$escapedRelativePath"",""False""")
            Write-Host "[Missing file] $relativePath"
            $missingItemCount++
        }
    }
}
finally {
    if ($csvWriter) {
        $csvWriter.Dispose()
    }
}

if ($missingItemCount -gt 0) {
    Write-Host "Missing items in check folder: $missingItemCount"
    Write-Host "CSV report saved to: $csvOutputPathResolved"
    exit 1
}

Write-Host "All directories and files from source folder exist in check folder."
Write-Host "CSV report saved to: $csvOutputPathResolved"
