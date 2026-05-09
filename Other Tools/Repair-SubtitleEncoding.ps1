param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Alias("BackupPath")]
    [string]$BackupRoot,

    [Alias("LogPath")]
    [string]$LogRoot,

    [switch]$Recursive,

    [switch]$WhatIf
)

# Přípony souborů s titulky
$SubtitleExtensions = @(".srt", ".sub", ".ass", ".ssa", ".vtt", ".txt")

function Get-FileEncoding {
    param(
        [string]$FilePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF) {
        return "UTF8-BOM"
    }

    if ($bytes.Length -ge 2 -and
        $bytes[0] -eq 0xFF -and
        $bytes[1] -eq 0xFE) {
        return "UTF-16LE"
    }

    if ($bytes.Length -ge 2 -and
        $bytes[0] -eq 0xFE -and
        $bytes[1] -eq 0xFF) {
        return "UTF-16BE"
    }

    # Pokus o validaci UTF-8 bez BOM
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

    try {
        $null = $utf8Strict.GetString($bytes)
        return "UTF8"
    }
    catch {
        return "Unknown"
    }
}

function Read-TextWithDetectedEncoding {
    param(
        [string]$FilePath,
        [string]$EncodingName
    )

    switch ($EncodingName) {
        "UTF8-BOM" {
            return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        }
        "UTF8" {
            return [System.IO.File]::ReadAllText($FilePath, [System.Text.UTF8Encoding]::new($false))
        }
        "UTF-16LE" {
            return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::Unicode)
        }
        "UTF-16BE" {
            return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::BigEndianUnicode)
        }
        default {
            # Nejčastější starší kódování českých titulků ve Windows
            return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::GetEncoding(1250))
        }
    }
}

function Get-SubtitleBackupPath {
    param(
        [string]$FilePath,
        [string]$SourceRoot,
        [string]$BackupRoot
    )

    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        return "$FilePath.bak"
    }

    $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)

    if ($fileFull.StartsWith($sourceRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $fileFull.Substring($sourceRootFull.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    else {
        $relativePath = Split-Path -Path $fileFull -Leaf
    }

    return Join-Path -Path $BackupRoot -ChildPath "$relativePath.bak"
}

function Write-RepairSubtitleLog {
    param(
        [string]$Message,
        [string]$LogFilePath
    )

    Write-Host $Message

    if (-not [string]::IsNullOrWhiteSpace($LogFilePath)) {
        Add-Content -LiteralPath $LogFilePath -Value $Message -Encoding UTF8
    }
}

if (-not (Test-Path $Path)) {
    throw "Zadaná složka neexistuje: $Path"
}

$sourceRoot = if ((Get-Item -LiteralPath $Path).PSIsContainer) {
    (Get-Item -LiteralPath $Path).FullName
}
else {
    (Get-Item -LiteralPath $Path).DirectoryName
}

$resolvedBackupPath = if (-not [string]::IsNullOrWhiteSpace($BackupRoot)) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupRoot)
}
else {
    $null
}

$logFilePath = $null
$changedFilesLogPath = $null

if (-not [string]::IsNullOrWhiteSpace($LogRoot)) {
    $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogRoot)

    if (-not (Test-Path -LiteralPath $resolvedLogPath)) {
        New-Item -Path $resolvedLogPath -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $modeName = if ($WhatIf) { "whatif" } else { "run" }
    $logFilePath = Join-Path -Path $resolvedLogPath -ChildPath "repair-subtitle-encoding-$modeName-$timestamp.log"

    New-Item -Path $logFilePath -ItemType File -Force | Out-Null

    if ($WhatIf) {
        $changedFilesLogPath = Join-Path -Path $resolvedLogPath -ChildPath "changed-files-$timestamp.txt"
        New-Item -Path $changedFilesLogPath -ItemType File -Force | Out-Null
    }

    Add-Content -LiteralPath $logFilePath -Value "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "Path: $Path" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "Recursive: $Recursive" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "WhatIf: $WhatIf" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "BackupRoot: $resolvedBackupPath" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "" -Encoding UTF8
}

$files = Get-ChildItem `
    -Path $Path `
    -File `
    -Recurse:$Recursive |
Where-Object { $SubtitleExtensions -contains $_.Extension.ToLowerInvariant() }

foreach ($file in $files) {
    $encoding = Get-FileEncoding -FilePath $file.FullName

    Write-RepairSubtitleLog -Message "Kontroluji: $($file.FullName) [$encoding]" -LogFilePath $logFilePath

    if ($encoding -eq "UTF8") {
        if (-not [string]::IsNullOrWhiteSpace($logFilePath)) {
            Add-Content -LiteralPath $logFilePath -Value "  OK - soubor uz je UTF-8 bez BOM" -Encoding UTF8
        }
        Write-Host "  OK - soubor už je UTF-8 bez BOM"
        continue
    }

    try {
        $text = Read-TextWithDetectedEncoding `
            -FilePath $file.FullName `
            -EncodingName $encoding

        $backupFilePath = Get-SubtitleBackupPath `
            -FilePath $file.FullName `
            -SourceRoot $sourceRoot `
            -BackupRoot $resolvedBackupPath
        $backupPath = $backupFilePath

        if ($WhatIf) {
            if (-not [string]::IsNullOrWhiteSpace($changedFilesLogPath)) {
                Add-Content -LiteralPath $changedFilesLogPath -Value "[$encoding] $($file.FullName)" -Encoding UTF8
            }
            if (-not [string]::IsNullOrWhiteSpace($logFilePath)) {
                Add-Content -LiteralPath $logFilePath -Value "  WhatIf: would convert to UTF-8 and create backup: $backupPath" -Encoding UTF8
            }
            Write-Host "  WhatIf: přeuložil bych do UTF-8 a vytvořil zálohu: $backupPath"
            continue
        }

        $backupDirectory = Split-Path -Path $backupPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($backupDirectory) -and -not (Test-Path -LiteralPath $backupDirectory)) {
            New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $file.FullName -Destination $backupPath -Force

        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8NoBom)

        if (-not [string]::IsNullOrWhiteSpace($logFilePath)) {
            Add-Content -LiteralPath $logFilePath -Value "  Converted to UTF-8. Backup: $backupPath" -Encoding UTF8
        }

        Write-Host "  Přeuloženo do UTF-8. Záloha: $backupPath"
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($logFilePath)) {
            Add-Content -LiteralPath $logFilePath -Value "  ERROR: failed to process file: $($file.FullName). Error: $($_.Exception.Message)" -Encoding UTF8
        }
        Write-Warning "  Nepodařilo se zpracovat soubor: $($file.FullName). Chyba: $($_.Exception.Message)"
    }
}

if (-not [string]::IsNullOrWhiteSpace($logFilePath)) {
    Add-Content -LiteralPath $logFilePath -Value "" -Encoding UTF8
    Add-Content -LiteralPath $logFilePath -Value "End: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
    Write-Host "Log: $logFilePath"

    if (-not [string]::IsNullOrWhiteSpace($changedFilesLogPath)) {
        Write-Host "Seznam souboru ke zmene: $changedFilesLogPath"
    }
}
