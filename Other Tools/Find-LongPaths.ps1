[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxDirectoryPathLength,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxFilePathLength,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvOutputPath = (Join-Path -Path (Get-Location) -ChildPath ("Find-LongPaths-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter(Mandatory = $false)]
    [switch]$UseRelativePathLength
)

function New-LongPathResult {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Directory', 'File')]
        [string]$ItemType,

        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $true)]
        [string]$EvaluatedPath,

        [Parameter(Mandatory = $true)]
        [int]$PathLength,

        [Parameter(Mandatory = $true)]
        [int]$Limit
    )

    [PSCustomObject]@{
        ItemType   = $ItemType
        FullPath   = $FullPath
        EvaluatedPath = $EvaluatedPath
        PathLength = $PathLength
        Limit      = $Limit
        ExceedsBy  = $PathLength - $Limit
    }
}

function Test-IsInSkippedDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$SkippedDirectories
    )

    foreach ($skippedDirectory in $SkippedDirectories) {
        if ($Path.StartsWith($skippedDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-EvaluatedPathInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseFolderPath,

        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $true)]
        [bool]$UseRelativeLength
    )

    if (-not $UseRelativeLength) {
        return [PSCustomObject]@{
            EvaluatedPath = $FullPath
            PathLength    = $FullPath.Length
        }
    }

    $relativePath = $FullPath.Substring($BaseFolderPath.Length).TrimStart('\')

    return [PSCustomObject]@{
        EvaluatedPath = $relativePath
        PathLength    = $relativePath.Length
    }
}

if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Error "Folder does not exist or is not a directory: $FolderPath"
    exit 1
}

$resolvedFolderPath = (Resolve-Path -Path $FolderPath).Path
$resolvedCsvOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvOutputPath)
$csvDirectory = Split-Path -Path $resolvedCsvOutputPath -Parent

if ($csvDirectory -and -not (Test-Path -Path $csvDirectory -PathType Container)) {
    New-Item -Path $csvDirectory -ItemType Directory -Force | Out-Null
}

$results = [System.Collections.Generic.List[object]]::new()
$skippedDirectories = [System.Collections.Generic.List[string]]::new()

foreach ($directory in Get-ChildItem -Path $resolvedFolderPath -Directory -Recurse) {
    $evaluatedPathInfo = Get-EvaluatedPathInfo -BaseFolderPath $resolvedFolderPath -FullPath $directory.FullName -UseRelativeLength $UseRelativePathLength.IsPresent
    $pathLength = $evaluatedPathInfo.PathLength

    if ($pathLength -gt $MaxDirectoryPathLength) {
        $result = New-LongPathResult -ItemType 'Directory' -FullPath $directory.FullName -EvaluatedPath $evaluatedPathInfo.EvaluatedPath -PathLength $pathLength -Limit $MaxDirectoryPathLength
        $results.Add($result)
        $skippedDirectories.Add($directory.FullName.TrimEnd('\') + '\')
        Write-Host "[Directory] Length=$pathLength Limit=$MaxDirectoryPathLength Path=$($evaluatedPathInfo.EvaluatedPath)"
    }
}

foreach ($file in Get-ChildItem -Path $resolvedFolderPath -File -Recurse) {
    if (Test-IsInSkippedDirectory -Path $file.FullName -SkippedDirectories $skippedDirectories) {
        continue
    }

    $evaluatedPathInfo = Get-EvaluatedPathInfo -BaseFolderPath $resolvedFolderPath -FullPath $file.FullName -UseRelativeLength $UseRelativePathLength.IsPresent
    $pathLength = $evaluatedPathInfo.PathLength

    if ($pathLength -gt $MaxFilePathLength) {
        $result = New-LongPathResult -ItemType 'File' -FullPath $file.FullName -EvaluatedPath $evaluatedPathInfo.EvaluatedPath -PathLength $pathLength -Limit $MaxFilePathLength
        $results.Add($result)
        Write-Host "[File] Length=$pathLength Limit=$MaxFilePathLength Path=$($evaluatedPathInfo.EvaluatedPath)"
    }
}

$results |
    Sort-Object -Property ItemType, PathLength, FullPath |
    Export-Csv -Path $resolvedCsvOutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Scanned folder: $resolvedFolderPath"
Write-Host "Long path items found: $($results.Count)"
Write-Host "CSV report saved to: $resolvedCsvOutputPath"

if ($results.Count -gt 0) {
    exit 1
}
