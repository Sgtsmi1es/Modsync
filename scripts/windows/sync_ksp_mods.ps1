<#
.SYNOPSIS
    Synchronizes Kerbal Space Program mods with a central server.
.DESCRIPTION
    This script synchronizes KSP mods between a Windows PC and a central SMB share.
    It logs all changes to a unified log file on the server.
#>

# Configuration
$ConfigPath = "$PSScriptRoot\..\..\config\sync_config.json"
$Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
$SmbShare = $Config.server.smb_share
$RemotePath = "$SmbShare\$($Config.sync_directories[0].remote_path)"
$LogFile = "$SmbShare\logs\modsync.log"
$ExcludeDirs = $Config.sync_directories[0].exclude_directories

# Function to find Steam installation path
function Find-SteamPath {
    $PossiblePaths = @(
        # Default Steam path
        "C:\Program Files (x86)\Steam",
        # Registry path for Steam
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    )

    foreach ($Path in $PossiblePaths) {
        if ($Path -and (Test-Path $Path)) {
            return $Path
        }
    }

    # If we can't find Steam, return null
    return $null
}

# Function to find KSP installation
function Find-KSPPath {
    $SteamPath = Find-SteamPath
    if (-not $SteamPath) {
        Write-SyncLog "ERROR: Could not find Steam installation"
        return $null
    }

    # Check default library location
    $DefaultLibrary = Join-Path -Path $SteamPath -ChildPath "steamapps\common\Kerbal Space Program"
    if (Test-Path $DefaultLibrary) {
        return Join-Path -Path $DefaultLibrary -ChildPath "GameData"
    }

    # Check for additional library folders
    $LibraryFoldersFile = Join-Path -Path $SteamPath -ChildPath "steamapps\libraryfolders.vdf"
    if (Test-Path $LibraryFoldersFile) {
        $Content = Get-Content -Path $LibraryFoldersFile -Raw
        
        # Extract paths from libraryfolders.vdf
        $Matches = [regex]::Matches($Content, '"path"\s+"([^"]+)"')
        foreach ($Match in $Matches) {
            $LibraryPath = $Match.Groups[1].Value.Replace("\\", "\")
            $KSPPath = Join-Path -Path $LibraryPath -ChildPath "steamapps\common\Kerbal Space Program"
            if (Test-Path $KSPPath) {
                return Join-Path -Path $KSPPath -ChildPath "GameData"
            }
        }
    }

    # If we can't find KSP, use the path from config
    return $Config.sync_directories[0].windows_path
}

# Ensure log directory exists
if (-not (Test-Path "$SmbShare\logs")) {
    New-Item -Path "$SmbShare\logs" -ItemType Directory -Force
}

# Function to write to log file
function Write-SyncLog {
    param (
        [string]$Message
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [Windows] $Message"
    
    # Write to console
    Write-Host $LogEntry
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogEntry
}

# Function to check if a path should be excluded
function Should-Exclude {
    param (
        [string]$Path
    )
    
    foreach ($excludeDir in $ExcludeDirs) {
        if ($Path -like "*\$excludeDir\*" -or $Path -like "*\$excludeDir") {
            return $true
        }
    }
    
    return $false
}

# Function to sync a directory
function Sync-Directory {
    param (
        [string]$Source,
        [string]$Destination
    )
    
    # Create destination if it doesn't exist
    if (-not (Test-Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force
        Write-SyncLog "Created directory: $Destination"
    }
    
    # Get all files and directories in source
    $Items = Get-ChildItem -Path $Source -Recurse
    
    foreach ($Item in $Items) {
        # Skip excluded directories
        if (Should-Exclude $Item.FullName) {
            continue
        }
        
        $RelativePath = $Item.FullName.Substring($Source.Length)
        $TargetPath = Join-Path -Path $Destination -ChildPath $RelativePath
        
        if ($Item.PSIsContainer) {
            # It's a directory
            if (-not (Test-Path $TargetPath)) {
                New-Item -Path $TargetPath -ItemType Directory -Force
                Write-SyncLog "Created directory: $RelativePath"
            }
        }
        else {
            # It's a file
            $SourceLastWrite = $Item.LastWriteTime
            
            if (Test-Path $TargetPath) {
                $TargetLastWrite = (Get-Item $TargetPath).LastWriteTime
                
                # If source is newer, copy it
                if ($SourceLastWrite -gt $TargetLastWrite) {
                    Copy-Item -Path $Item.FullName -Destination $TargetPath -Force
                    Write-SyncLog "Updated file: $RelativePath"
                }
            }
            else {
                # Target doesn't exist, copy it
                Copy-Item -Path $Item.FullName -Destination $TargetPath -Force
                Write-SyncLog "Copied new file: $RelativePath"
            }
        }
    }
    
    # Check for files in destination that don't exist in source (for deletion)
    $DestItems = Get-ChildItem -Path $Destination -Recurse
    
    foreach ($DestItem in $DestItems) {
        if ($DestItem.PSIsContainer) {
            continue  # Skip directories for deletion check
        }
        
        $RelativePath = $DestItem.FullName.Substring($Destination.Length)
        $SourcePath = Join-Path -Path $Source -ChildPath $RelativePath
        
        # Skip excluded directories
        if (Should-Exclude $SourcePath) {
            continue
        }
        
        if (-not (Test-Path $SourcePath)) {
            # Source doesn't exist, delete from destination
            Remove-Item -Path $DestItem.FullName -Force
            Write-SyncLog "Deleted file: $RelativePath"
        }
    }
}

# Main execution
try {
    Write-SyncLog "Starting KSP mod synchronization"
    
    # Check if SMB share is accessible
    if (-not (Test-Path $SmbShare)) {
        Write-SyncLog "ERROR: Cannot access SMB share at $SmbShare"
        exit 1
    }
    
    # Find KSP installation
    $LocalPath = Find-KSPPath
    if (-not $LocalPath) {
        Write-SyncLog "ERROR: Could not find KSP installation. Using path from config."
        $LocalPath = $Config.sync_directories[0].windows_path
    }
    
    Write-SyncLog "Using KSP GameData path: $LocalPath"
    
    # Check if local GameData directory exists
    if (-not (Test-Path $LocalPath)) {
        Write-SyncLog "ERROR: Cannot access local GameData directory at $LocalPath"
        exit 1
    }
    
    # Ensure remote directory exists
    if (-not (Test-Path $RemotePath)) {
        New-Item -Path $RemotePath -ItemType Directory -Force
        Write-SyncLog "Created remote directory: $RemotePath"
    }
    
    # First sync from local to remote (upload new mods)
    Write-SyncLog "Syncing from local to remote..."
    Sync-Directory -Source $LocalPath -Destination $RemotePath
    
    # Then sync from remote to local (download mods from other machines)
    Write-SyncLog "Syncing from remote to local..."
    Sync-Directory -Source $RemotePath -Destination $LocalPath
    
    Write-SyncLog "Synchronization completed successfully"
}
catch {
    Write-SyncLog "ERROR: $($_.Exception.Message)"
    exit 1
}
