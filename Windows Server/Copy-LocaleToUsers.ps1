param (
    [string[]]$ExcludeUsers = @()
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Must run elevated
# ------------------------------------------------------------

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run PowerShell as Administrator."
}


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$SourceUser = $env:USERNAME
$SourcePath = "HKCU:\Control Panel\International"

# Always excluded profiles
$BuiltInExclusions = @(
    "Default",
    "Default User",
    "Public",
    "All Users",
    "defaultuser0",
    "systemprofile",
    "LocalService",
    "NetworkService",
    ".NET v4.5",
    ".NET v4.5 Classic"
)

$AllExclusions = $ExcludeUsers + $BuiltInExclusions


# ------------------------------------------------------------
# Verify source
# ------------------------------------------------------------

if (-not (Test-Path $SourcePath)) {
    throw "Source regional settings not found."
}

$SourceSettings = Get-ItemProperty $SourcePath

Write-Host ""
Write-Host "Source user: $SourceUser" -ForegroundColor Cyan
Write-Host "Source regional format:" -ForegroundColor Cyan

$SourceSettings |
    Select-Object LocaleName,
                  Locale,
                  sLanguage,
                  sCountry,
                  sShortDate,
                  sLongDate,
                  sShortTime,
                  sTimeFormat,
                  sDecimal,
                  sThousand,
                  sCurrency,
                  iFirstDayOfWeek |
    Format-List


# ------------------------------------------------------------
# Get user profiles
# ------------------------------------------------------------

$Profiles = Get-CimInstance Win32_UserProfile |
    Where-Object {
        -not $_.Special -and
        $_.LocalPath -and
        (Test-Path $_.LocalPath)
    }


Write-Host "Profiles to process:" -ForegroundColor Cyan

foreach ($Profile in $Profiles) {

    $UserName = Split-Path $Profile.LocalPath -Leaf

    if (
        $UserName -ne $SourceUser -and
        -not $Profile.Loaded -and
        $AllExclusions -notcontains $UserName
    ) {
        Write-Host "  $UserName"
    }
}

Write-Host ""


# ------------------------------------------------------------
# Process profiles
# ------------------------------------------------------------

foreach ($Profile in $Profiles) {

    $UserName = Split-Path $Profile.LocalPath -Leaf


    # Skip source account
    if ($UserName -eq $SourceUser) {

        Write-Host "SKIP: $UserName (source user)" `
            -ForegroundColor DarkGray

        continue
    }


    # Skip exclusions
    if ($AllExclusions -contains $UserName) {

        Write-Host "SKIP: $UserName (excluded)" `
            -ForegroundColor Yellow

        continue
    }


    # Skip profiles that are currently loaded for a signed-in user
    if ($Profile.Loaded) {

        Write-Host "SKIP: $UserName (profile is loaded; user may be signed in)" `
            -ForegroundColor Yellow

        continue
    }


    Write-Host ""
    Write-Host "Processing: $UserName" `
        -ForegroundColor Cyan


    $HiveName = "RegionalTemp_$($Profile.SID.Replace('-', '_'))"

    $NtUserPath = Join-Path `
        $Profile.LocalPath `
        "NTUSER.DAT"

    $LoadedByUs = $false
    $CopyFailed = $false


    try {

        # ----------------------------------------------------
        # Is user hive already loaded?
        # ----------------------------------------------------

        if (Test-Path "Registry::HKEY_USERS\$($Profile.SID)") {

            Write-Host "SKIP: $UserName (profile became loaded; user may be signed in)" `
                -ForegroundColor Yellow

            continue

        }
        else {

            # ------------------------------------------------
            # Load NTUSER.DAT
            # ------------------------------------------------

            if (-not (Test-Path $NtUserPath)) {

                Write-Warning "NTUSER.DAT not found. Skipping."

                continue
            }


            Write-Host "  Loading: $NtUserPath"


            $Process = Start-Process `
                -FilePath "reg.exe" `
                -ArgumentList @(
                    "load",
                    "HKU\$HiveName",
                    "`"$NtUserPath`""
                ) `
                -Wait `
                -PassThru `
                -NoNewWindow


            if ($Process.ExitCode -ne 0) {

                throw "reg.exe load failed with exit code $($Process.ExitCode)."
            }


            $LoadedByUs = $true

            $TargetPath =
                "Registry::HKEY_USERS\$HiveName\Control Panel\International"
        }


        # ----------------------------------------------------
        # Create target key if necessary
        # ----------------------------------------------------

        if (-not (Test-Path $TargetPath)) {

            New-Item `
                -Path $TargetPath `
                -Force |
                Out-Null
        }


        # ----------------------------------------------------
        # Copy International values
        # ----------------------------------------------------

        Write-Host "  Copying regional settings..."


        foreach ($Property in $SourceSettings.PSObject.Properties) {

            if ($Property.Name -like "PS*") {
                continue
            }


            try {

                Set-ItemProperty `
                    -Path $TargetPath `
                    -Name $Property.Name `
                    -Value $Property.Value `
                    -Force `
                    -ErrorAction Stop

            }
            catch {

                $CopyFailed = $true

                Write-Warning `
                    "Could not copy '$($Property.Name)': $($_.Exception.Message)"
            }
        }


        # ----------------------------------------------------
        # Copy International\User Profile
        # ----------------------------------------------------

        $SourceUserProfile =
            "$SourcePath\User Profile"

        $TargetUserProfile =
            "$TargetPath\User Profile"


        if (Test-Path $SourceUserProfile) {

            if (-not (Test-Path $TargetUserProfile)) {

                New-Item `
                    -Path $TargetUserProfile `
                    -Force |
                    Out-Null
            }


            $UserProfileSettings =
                Get-ItemProperty $SourceUserProfile


            foreach (
                $Property in
                $UserProfileSettings.PSObject.Properties
            ) {

                if ($Property.Name -like "PS*") {
                    continue
                }


                try {

                    Set-ItemProperty `
                        -Path $TargetUserProfile `
                        -Name $Property.Name `
                        -Value $Property.Value `
                        -Force `
                        -ErrorAction Stop

                }
                catch {

                    $CopyFailed = $true

                    Write-Warning `
                        "Could not copy User Profile '$($Property.Name)': $($_.Exception.Message)"
                }
            }
        }


        if ($CopyFailed) {

            Write-Host `
                "  PARTIAL: Some regional settings could not be copied." `
                -ForegroundColor Yellow
        }
        else {

            Write-Host `
                "  Regional settings copied successfully." `
                -ForegroundColor Green
        }

    }
    catch {

        Write-Host `
            "  FAILED: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
    finally {

        # ----------------------------------------------------
        # Unload hive if we loaded it
        # ----------------------------------------------------

        if ($LoadedByUs) {

            # Release PowerShell registry handles
            Remove-Variable TargetPath `
                -ErrorAction SilentlyContinue

            Remove-Variable TargetUserProfile `
                -ErrorAction SilentlyContinue

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Start-Sleep -Milliseconds 500


            Write-Host "  Unloading registry hive..."


            $UnloadProcess = Start-Process `
                -FilePath "reg.exe" `
                -ArgumentList @(
                    "unload",
                    "HKU\$HiveName"
                ) `
                -Wait `
                -PassThru `
                -NoNewWindow


            if ($UnloadProcess.ExitCode -eq 0) {

                Write-Host `
                    "  Hive unloaded successfully." `
                    -ForegroundColor DarkGray
            }
            else {

                Write-Warning `
                    "Could not unload HKU\$HiveName. Exit code: $($UnloadProcess.ExitCode)"
            }
        }
    }
}


Write-Host ""
Write-Host "Finished." -ForegroundColor Green
Write-Host `
    "Users should sign out and sign in again for the new regional format to apply."