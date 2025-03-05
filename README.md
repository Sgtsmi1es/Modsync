# Modsync

A cross-platform file synchronization tool that backs up folders from various clients to a central Unraid NFS/SMB share, with special support for Kerbal Space Program mod synchronization.

## Features

- Bidirectional synchronization between clients and server
- Support for Windows, Mac, and Linux
- Automatic Steam game path detection
- Preservation of directory structure
- Conflict resolution based on file modification times
- Unified logging of all sync operations
- Exclusion of unnecessary game files

## KSP Mod Synchronization

Modsync includes specialized scripts for keeping Kerbal Space Program mods in sync across multiple computers:

- Automatically detects KSP installation location on Windows and Mac
- Synchronizes mod folders while excluding base game files
- Provides status reporting to track sync operations
- Works with both NFS (Mac/Linux) and SMB (Windows) protocols

### Directory Structure

When syncing KSP mods, the following structure is created on the server:

```
/mnt/bridger_storage/
│
├── KSP_Mods/
│   └── GameData/
│       ├── ModFolder1/
│       ├── ModFolder2/
│       └── ... (other mod folders)
│
└── logs/
    └── modsync.log
```

## Usage

### Windows

1. Copy the `scripts/windows/sync_ksp_mods.ps1` script to your Windows PC
2. Open PowerShell as Administrator
3. Run: `.\sync_ksp_mods.ps1`

### Mac

1. Copy the `scripts/mac/sync_ksp_mods.sh` script to your Mac
2. Open Terminal
3. Run: `./sync_ksp_mods.sh`

### Linux Server

To check sync status:

```bash
~/bridger/Modsync/scripts/linux/check_sync_status.sh
```

## Configuration

The main configuration file is located at `config/sync_config.json`. It contains:

- Server connection details (NFS/SMB)
- Sync directories configuration
- Exclusion patterns
- Sync interval and conflict resolution settings

## Setup

See the documentation in the `docs` directory for platform-specific setup instructions.

## Requirements

- Windows: PowerShell 5.0+
- Mac: Bash, rsync, jq
- Linux: Bash, rsync, jq
- Server: NFS and/or SMB share

## Future Enhancements

- Web-based status dashboard
- Email notifications for sync failures
- Scheduled automatic synchronization
- Support for additional games and applications