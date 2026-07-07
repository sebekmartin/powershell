#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Repairs user folder ownership and permissions in redirected user profiles.

.DESCRIPTION
    This script processes user folders in E:\HOME, temporarily takes ownership as DOMAIN\admin,
    propagates permissions from the user folder to all subfolders and files, then returns 
    ownership back to the original user.

.PARAMETER HomeBasePath
    The base path where user folders are located. Default is E:\HOME

.PARAMETER AdminAccount
    The administrator account to use for temporary ownership. Default is DOMAIN\admin

.EXAMPLE
    .\Repair-UserRights.ps1
    Processes all user folders in E:\HOME with default settings

.EXAMPLE
    .\Repair-UserRights.ps1 -HomeBasePath "E:\HOME" -AdminAccount "DOMAIN\admin"
    Processes user folders with specified parameters
#>

param(
    [string]$HomeBasePath = "",
    [string]$AdminAccount = ""
)

# Function to write log messages with timestamp
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Function to take ownership of a path
function Set-Ownership {
    param(
        [string]$Path,
        [string]$Owner
    )
    
    try {
        $result = & takeown /f "$Path" /r /d y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully took ownership of: $Path" "SUCCESS"
            
            # Set the specific owner using icacls
            $result = & icacls "$Path" /setowner "$Owner" /t /c 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully set owner to $Owner for: $Path" "SUCCESS"
                return $true
            }
            else {
                Write-Log "Failed to set owner to $Owner for: $Path. Error: $result" "ERROR"
                return $false
            }
        }
        else {
            Write-Log "Failed to take ownership of: $Path. Error: $result" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Exception taking ownership of $Path : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to propagate permissions from parent to children
function Set-PermissionPropagation {
    param(
        [string]$Path
    )
    
    try {
        # Reset permissions to inherit from parent and propagate to children
        $result = & icacls "$Path" /reset /t /c 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully reset and propagated permissions for: $Path" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Failed to propagate permissions for: $Path. Error: $result" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Exception propagating permissions for $Path : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to get the current owner of a folder
function Get-CurrentOwner {
    param(
        [string]$Path
    )
    
    try {
        # Get the current owner using Get-Acl
        $acl = Get-Acl -Path $Path
        $owner = $acl.Owner
        
        Write-Log "Current owner of $Path is: $owner" "INFO"
        return $owner
    }
    catch {
        Write-Log "Exception getting current owner of $Path : $($_.Exception.Message)" "ERROR"
        
        # Fallback: try using icacls to get owner information
        try {
            $result = & icacls "$Path" 2>&1
            if ($LASTEXITCODE -eq 0) {
                # Parse icacls output to extract owner
                $lines = $result -split "`n"
                foreach ($line in $lines) {
                    if ($line -match "^\s*(.+?):\(F\)") {
                        $potentialOwner = $matches[1].Trim()
                        if ($potentialOwner -like "DOMAIN\*") {
                            Write-Log "Found owner via icacls: $potentialOwner" "INFO"
                            return $potentialOwner
                        }
                    }
                }
            }
        }
        catch {
            Write-Log "Fallback method also failed for $Path : $($_.Exception.Message)" "ERROR"
        }
        
        return $null
    }
}

# Function to restore ownership and set full control permissions
function Restore-Ownership {
    param(
        [string]$Path,
        [string]$OriginalOwner
    )
    
    try {
        # First, grant the original user Full Control permissions
        Write-Log "Granting Full Control permissions to $OriginalOwner for: $Path" "INFO"
        $result = & icacls "$Path" /grant "${OriginalOwner}:(OI)(CI)F" /t /c 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully granted Full Control permissions to $OriginalOwner for: $Path" "SUCCESS"
        }
        else {
            Write-Log "Failed to grant Full Control permissions to $OriginalOwner for: $Path. Error: $result" "WARNING"
        }
        
        # Then restore ownership
        $result = & icacls "$Path" /setowner "$OriginalOwner" /t /c 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully restored ownership to $OriginalOwner for: $Path" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Failed to restore ownership to $OriginalOwner for: $Path. Error: $result" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Exception restoring ownership for $Path : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main script execution
Write-Log "Starting user rights repair process"
Write-Log "Home base path: $HomeBasePath"
Write-Log "Admin account: $AdminAccount"

# Check if the HOME directory exists
if (-not (Test-Path $HomeBasePath)) {
    Write-Log "Home base path does not exist: $HomeBasePath" "ERROR"
    exit 1
}

# Get all user folders in the HOME directory
$userFolders = Get-ChildItem -Path $HomeBasePath -Directory

if ($userFolders.Count -eq 0) {
    Write-Log "No user folders found in: $HomeBasePath" "WARNING"
    exit 0
}

Write-Log "Found $($userFolders.Count) user folders to process"

# Process each user folder
foreach ($userFolder in $userFolders) {
    $userFolderPath = $userFolder.FullName
    $userName = $userFolder.Name
    
    Write-Log "Processing user folder: $userFolderPath (Folder: $userName)"
    
    # Full mode - complete ownership and permission repair process
    # Get the current owner of the user folder
    $originalOwner = Get-CurrentOwner -Path $userFolderPath
    if (-not $originalOwner) {
        Write-Log "Could not determine current owner for: $userFolderPath. Skipping to next user." "ERROR"
        continue
    }
    
    # Verify the owner belongs to DOMAIN domain
    if ($originalOwner -notlike "DOMAIN\*") {
        Write-Log "Owner $originalOwner does not belong to DOMAIN domain. Skipping to next user." "WARNING"
        continue
    }
    
    Write-Log "Original owner: $originalOwner"
    
    # Step 1: Take ownership as admin
    Write-Log "Step 1: Taking ownership as $AdminAccount"
    if (-not (Set-Ownership -Path $userFolderPath -Owner $AdminAccount)) {
        Write-Log "Failed to take ownership for user: $userName. Skipping to next user." "ERROR"
        continue
    }
    
    # Step 2: Propagate permissions from user folder to all subfolders and files
    Write-Log "Step 2: Propagating permissions from parent folder"
    if (-not (Set-PermissionPropagation -Path $userFolderPath)) {
        Write-Log "Failed to propagate permissions for user: $userName" "ERROR"
    }
    
    # Step 3: Restore ownership and grant Full Control to original user
    Write-Log "Step 3: Restoring ownership and granting Full Control to $originalOwner"
    if (-not (Restore-Ownership -Path $userFolderPath -OriginalOwner $originalOwner)) {
        Write-Log "Failed to restore ownership for user: $userName" "ERROR"
    }
    
    Write-Log "Completed processing for user: $userName"
    Write-Log "----------------------------------------"
}

Write-Log "User rights repair process completed"