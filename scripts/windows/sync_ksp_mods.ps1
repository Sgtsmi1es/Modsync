<#
.SYNOPSIS
    Synchronizes Kerbal Space Program mods with a central server.
.DESCRIPTION
    This script synchronizes KSP mods between a Windows PC and a central SMB share.
    It logs all changes to a unified log file on the server.
#>

# Configuration
$ConfigPath = "$PSScriptRoot\..\..\config\sync_config.json"

# Check if config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found at $ConfigPath"
    exit 1
}

$Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
$SmbShare = $Config.server.smb_share
$RemotePath = "$SmbShare\$($Config.sync_directories[0].remote_path)"
$LogFile = "$SmbShare\logs\modsync.log"
$ExcludeDirs = $Config.sync_directories[0].exclude_directories

# Function to find Steam installation path
function Find-SteamPath {
    $PossiblePaths = @(
        # Default Steam path
        "C:\Program Files (x86)\Steam"
    )
    
    # Try to get Steam path from registry
    $SteamRegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    try {
        $SteamPathFromRegistry = (Get-ItemProperty -Path $SteamRegistryPath -Name "InstallPath" -ErrorAction Stop).InstallPath
        if ($SteamPathFromRegistry) {
            $PossiblePaths += $SteamPathFromRegistry
        }
    } catch {
        Write-Host "Could not retrieve Steam path from registry: $($_.Exception.Message)"
    }

    foreach ($Path in $PossiblePaths) {
        if ($Path -and (Test-Path $Path)) {
            return $Path
        }
    }

    # If we can't find Steam, return null
    return $null
}

# Function to ensure path ends with a trailing backslash
function Ensure-TrailingBackslash {
    param ([string]$Path)
    
    if (-not $Path.EndsWith('\')) {
        return "$Path\"
    }
    return $Path
}

# Function to get relative path more robustly
function Get-RelativePath {
    param (
        [string]$BasePath,
        [string]$FullPath
    )
    
    $BasePath = Ensure-TrailingBackslash $BasePath
    if ($FullPath.StartsWith($BasePath)) {
        return $FullPath.Substring($BasePath.Length)
    }
    
    # Fallback to more complex relative path calculation if needed
    try {
        # For PowerShell 6.0+ and .NET Core 2.0+
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
        }
    } catch {
        Write-SyncLog "WARNING: Error calculating relative path: $($_.Exception.Message)"
    }
    
    # Last resort fallback
    return $FullPath.Substring($BasePath.Length)
}

# Function to check if a path should be excluded (more robust)
function Should-Exclude {
    param (
        [string]$Path
    )
    
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($excludeDir in $ExcludeDirs) {
        # More precise matching for exact directory names
        $excludePattern = [regex]::Escape($excludeDir)
        if ($FullPath -match "\\$excludePattern(\\|$)") {
            return $true
        }
    }
    
    return $false
}

# Function to handle file conflicts
function Resolve-FileConflict {
    param (
        [string]$SourcePath,
        [string]$DestPath,
        [DateTime]$SourceTime,
        [DateTime]$DestTime
    )
    
    # Default strategy: newest wins
    if ($SourceTime -gt $DestTime) {
        return "Source"
    } elseif ($DestTime -gt $SourceTime) {
        return "Destination"
    }
    
    # If timestamps are identical (rare), use file size as tiebreaker
    $SourceSize = (Get-Item $SourcePath).Length
    $DestSize = (Get-Item $DestPath).Length
    
    if ($SourceSize -ne $DestSize) {
        return "Source"  # Prefer source in case of doubt
    }
    
    # If everything is identical, no action needed
    return "Equal"
}

# Function to sync a directory with performance optimization
function Sync-Directory {
    param (
        [string]$Source,
        [string]$Destination,
        [switch]$CreateBackups = $false
    )
    
    # Ensure paths end with trailing backslash for consistent relative path calculation
    $Source = Ensure-TrailingBackslash $Source
    $Destination = Ensure-TrailingBackslash $Destination
    
    # Create destination if it doesn't exist
    if (-not (Test-Path $Destination)) {
        try {
            New-Item -Path $Destination -ItemType Directory -Force
            Write-SyncLog "Created directory: $Destination"
        } catch {
            Write-SyncLog "ERROR: Failed to create directory $Destination: $($_.Exception.Message)"
            return
        }
    }
    
    # Store source items in a hashtable for faster lookup
    $SourceItems = @{}
    $SourceDirs = @{}
    
    Write-SyncLog "Scanning source directory..."
    try {
        Get-ChildItem -Path $Source -Recurse -ErrorAction Stop | ForEach-Object {
            if (Should-Exclude $_.FullName) {
                return
            }
            
            if ($_.PSIsContainer) {
                $SourceDirs[$_.FullName] = $_
            } else {
                $SourceItems[$_.FullName] = $_
            }
        }
    } catch {
        Write-SyncLog "ERROR: Failed to scan source directory: $($_.Exception.Message)"
        return
    }
    
    # Create all directories first
    foreach ($DirPath in $SourceDirs.Keys) {
        $RelativePath = Get-RelativePath -BasePath $Source -FullPath $DirPath
        $TargetPath = Join-Path -Path $Destination -ChildPath $RelativePath
        
        if (-not (Test-Path $TargetPath)) {
            try {
                New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
                Write-SyncLog "Created directory: $RelativePath"
            } catch {
                Write-SyncLog "ERROR: Failed to create directory $TargetPath: $($_.Exception.Message)"
            }
        }
    }
    
    # Copy files that are new or modified
    foreach ($FilePath in $SourceItems.Keys) {
        $Item = $SourceItems[$FilePath]
        $RelativePath = Get-RelativePath -BasePath $Source -FullPath $FilePath
        $TargetPath = Join-Path -Path $Destination -ChildPath $RelativePath
        
        $SourceLastWrite = $Item.LastWriteTime
        
        if (Test-Path $TargetPath) {
            try {
                $TargetLastWrite = (Get-Item $TargetPath -ErrorAction Stop).LastWriteTime
                
                # Resolve conflict
                $Resolution = Resolve-FileConflict -SourcePath $FilePath -DestPath $TargetPath -SourceTime $SourceLastWrite -DestTime $TargetLastWrite
                
                if ($Resolution -eq "Source") {
                    # If creating backups is enabled
                    if ($CreateBackups) {
                        $BackupPath = "$TargetPath.bak"
                        Copy-Item -Path $TargetPath -Destination $BackupPath -Force
                        Write-SyncLog "Created backup: $RelativePath.bak"
                    }
                    
                    Copy-Item -Path $FilePath -Destination $TargetPath -Force
                    Write-SyncLog "Updated file: $RelativePath"
                } elseif ($Resolution -eq "Equal") {
                    # Files are identical, no action needed
                }
            } catch {
                Write-SyncLog "ERROR: Failed to check or update file $TargetPath: $($_.Exception.Message)"
            }
        } else {
            # Target doesn't exist, copy it
            try {
                Copy-Item -Path $FilePath -Destination $TargetPath -Force
                Write-SyncLog "Copied new file: $RelativePath"
            } catch {
                Write-SyncLog "ERROR: Failed to copy file to $TargetPath: $($_.Exception.Message)"
            }
        }
    }
    
    # Store destination items in a hashtable for faster lookup
    $DestItems = @{}
    
    Write-SyncLog "Scanning destination directory for obsolete files..."
    try {
        Get-ChildItem -Path $Destination -Recurse -File -ErrorAction Stop | ForEach-Object {
            if (-not (Should-Exclude $_.FullName)) {
                $DestItems[$_.FullName] = $_
            }
        }
    } catch {
        Write-SyncLog "ERROR: Failed to scan destination directory: $($_.Exception.Message)"
        return
    }
    
    # Check for files in destination that don't exist in source (for deletion)
    foreach ($DestPath in $DestItems.Keys) {
        $RelativePath = Get-RelativePath -BasePath $Destination -FullPath $DestPath
        $SourcePath = Join-Path -Path $Source -ChildPath $RelativePath
        
        if (-not $SourceItems.ContainsKey($SourcePath) -and -not (Should-Exclude $SourcePath)) {
            # Source doesn't exist, delete from destination
            try {
                # If creating backups is enabled
                if ($CreateBackups) {
                    $BackupPath = "$DestPath.bak"
                    Copy-Item -Path $DestPath -Destination $BackupPath -Force
                    Write-SyncLog "Created backup before deletion: $RelativePath.bak"
                }
                
                Remove-Item -Path $DestPath -Force
                Write-SyncLog "Deleted file: $RelativePath"
            } catch {
                Write-SyncLog "ERROR: Failed to delete file $DestPath: $($_.Exception.Message)"
            }
        }
    }
}

# Function to find KSP installation with more robust libraryfolders.vdf parsing
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
        $LibraryPaths = @()
        
        # Try multiple parsing approaches for different Steam versions
        
        # Approach 1: Extract paths using regex for newer format
        $Matches = [regex]::Matches($Content, '"path"\s+"([^"]+)"')
        foreach ($Match in $Matches) {
            $LibraryPaths += $Match.Groups[1].Value.Replace("\\", "\")
        }
        
        # Approach 2: Try newer format with numbered entries
        if ($LibraryPaths.Count -eq 0) {
            $Matches = [regex]::Matches($Content, '"(\d+)"\s+{[^}]*"path"\s+"([^"]+)"')
            foreach ($Match in $Matches) {
                $LibraryPaths += $Match.Groups[2].Value.Replace("\\", "\")
            }
        }
        
        # Approach 3: Try older format
        if ($LibraryPaths.Count -eq 0) {
            $Matches = [regex]::Matches($Content, '"(\d+)"\s+"([^"]+)"')
            foreach ($Match in $Matches) {
                if ($Match.Groups[1].Value -match '^\d+$') {
                    $LibraryPaths += $Match.Groups[2].Value.Replace("\\", "\")
                }
            }
        }
        
        # Check each library path for KSP
        foreach ($LibraryPath in $LibraryPaths) {
            $KSPPath = Join-Path -Path $LibraryPath -ChildPath "steamapps\common\Kerbal Space Program"
            if (Test-Path $KSPPath) {
                return Join-Path -Path $KSPPath -ChildPath "GameData"
            }
        }
        
        # If no libraries found, log a warning
        if ($LibraryPaths.Count -eq 0) {
            Write-SyncLog "WARNING: Could not parse Steam library folders file. Format may have changed."
        } else {
            Write-SyncLog "WARNING: KSP not found in any Steam library. Checked paths: $($LibraryPaths -join ', ')"
        }
    }

    # If we can't find KSP, use the path from config
    Write-SyncLog "Using KSP path from config file as fallback."
    return $Config.sync_directories[0].windows_path
}

# Ensure log directory exists
if (-not (Test-Path "$SmbShare\logs")) {
    try {
        New-Item -Path "$SmbShare\logs" -ItemType Directory -Force
    } catch {
        Write-Error "Failed to create log directory: $($_.Exception.Message)"
        exit 1
    }
}

# Function to write to log database and local backup
function Write-SyncLog {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $ComputerName = $env:COMPUTERNAME
    $ProcessId = $PID
    $SessionId = $script:SyncSessionId  # Defined at script start
    $LogEntry = "[$Timestamp] [$ComputerName:$ProcessId:$SessionId] [$Level] $Message"
    
    # Write to console with color based on level
    switch ($Level) {
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
        default { Write-Host $LogEntry }
    }
    
    # Always write to local backup log
    $LocalLogDir = "$PSScriptRoot\logs"
    if (-not (Test-Path $LocalLogDir)) {
        New-Item -Path $LocalLogDir -ItemType Directory -Force | Out-Null
    }
    $LocalLogFile = "$LocalLogDir\local_sync.log"
    Add-Content -Path $LocalLogFile -Value $LogEntry
    
    # Try to log to database
    try {
        $LogData = @{
            timestamp = $Timestamp
            computer = $ComputerName
            process_id = $ProcessId
            session_id = $SessionId
            platform = "Windows"
            level = $Level
            message = $Message
        }
        
        $JsonData = $LogData | ConvertTo-Json
        Invoke-RestMethod -Uri "$LogServerUrl/api/logs" -Method Post -Body $JsonData -ContentType "application/json" -TimeoutSec 5
    }
    catch {
        # If database logging fails, write to SMB share as fallback
        try {
            Add-Content -Path $LogFile -Value "$LogEntry [DB_FALLBACK]"
        }
        catch {
            Write-Host "WARNING: Failed to write to both database and SMB log: $($_.Exception.Message)" -ForegroundColor Red
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
        try {
            New-Item -Path $RemotePath -ItemType Directory -Force
            Write-SyncLog "Created remote directory: $RemotePath"
        } catch {
            Write-SyncLog "ERROR: Failed to create remote directory: $($_.Exception.Message)"
            exit 1
        }
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
