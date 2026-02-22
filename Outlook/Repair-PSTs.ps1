# === Configuration ===
# Path to folder containing PST files
$PstFolder = "D:\PSTs\"

# Path to ScanPST.exe (adjust to your Outlook version & installation)
$ScanPstPath = "C:\Program Files\Microsoft Office\root\Office16\SCANPST.EXE"

# Main summary log file
$LogFile = "$PstFolder\ScanPST_log.txt"

# Folder for per-PST log and backup files
$OutputFolder = Join-Path $PstFolder "ScanPST_Results"
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

# === Script ===
if (-not (Test-Path $ScanPstPath)) {
    Write-Host "ERROR: ScanPST.exe not found at: $ScanPstPath"
    exit 1
}

# Clear old summary log
"" | Out-File $LogFile

# Get all PST files in folder and subfolders
$PstFiles = Get-ChildItem -Path $PstFolder -Filter *.pst -File -Recurse

if ($PstFiles.Count -eq 0) {
    Write-Host "No PST files found in $PstFolder or subfolders."
    exit 0
}

foreach ($File in $PstFiles) {
    # Create safe filename for log & backup
    $RelativePath = $File.FullName.Substring($PstFolder.Length).TrimStart('\')
    $SafeName = ($RelativePath -replace '[\\/:*?"<>|]', '_') -replace '\.pst$', ''

    $PstLogFile = Join-Path $OutputFolder "$SafeName.log"
    $BackupFile = Join-Path $OutputFolder "$SafeName.bak"

    Write-Host "Repairing: $RelativePath"
    Add-Content $LogFile "[$(Get-Date)] Starting repair of $($File.FullName)"

    # Build arguments (silent, with log & optional backup)
    $Args = @(
        '-file', "`"$($File.FullName)`""
        '-log', 'replace'
        '-rescan', '3'
        '-force'
        '-silent'
        # '-backupfile', "`"$BackupFile`""
    )

    # Run ScanPST silently
    Start-Process -FilePath $ScanPstPath -ArgumentList $Args -Wait -NoNewWindow

    Add-Content $LogFile "[$(Get-Date)] Finished repair of $($File.FullName)"
    Add-Content $LogFile "--------------------------------------------"
}

Write-Host "`nAll PST repairs finished."
Write-Host "Summary log: $LogFile"
Write-Host "Per-file logs & backups: $OutputFolder"
