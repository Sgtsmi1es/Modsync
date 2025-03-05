#!/bin/bash
#
# Synchronizes Kerbal Space Program mods with a central server.
# This script synchronizes KSP mods between a Mac and a central NFS share.
# It logs all changes to a unified log file on the server.

# Exit on error
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../../config/sync_config.json"
NFS_SERVER=$(jq -r '.server.nfs_server' "$CONFIG_PATH")
NFS_SHARE=$(jq -r '.server.nfs_share' "$CONFIG_PATH")
MOUNT_POINT=$(jq -r '.server.mount_point' "$CONFIG_PATH")
REMOTE_PATH="$MOUNT_POINT/$(jq -r '.sync_directories[0].remote_path' "$CONFIG_PATH")"
CONFIG_LOCAL_PATH=$(jq -r '.sync_directories[0].mac_path' "$CONFIG_PATH")
LOG_FILE="$MOUNT_POINT/logs/modsync.log"

# Get exclude directories as an array
EXCLUDE_DIRS=()
for dir in $(jq -r '.sync_directories[0].exclude_directories[]' "$CONFIG_PATH"); do
    EXCLUDE_DIRS+=("$dir")
done

# Function to write to log file
write_log() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] [Mac] $message"
    
    # Write to console
    echo "$log_entry"
    
    # Write to log file
    echo "$log_entry" >> "$LOG_FILE"
}

# Function to find Steam installation and KSP path
find_ksp_path() {
    # Get current user
    local current_user=$(whoami)
    
    # Common Steam installation locations on Mac
    local steam_paths=(
        "/Users/$current_user/Library/Application Support/Steam"
        "/Users/$current_user/Documents/Steam"
    )
    
    # Check for Steam installation
    local steam_path=""
    for path in "${steam_paths[@]}"; do
        if [ -d "$path" ]; then
            steam_path="$path"
            break
        fi
    done
    
    if [ -z "$steam_path" ]; then
        write_log "Could not find Steam installation. Using path from config."
        echo "$CONFIG_LOCAL_PATH"
        return
    fi
    
    # Check default library location
    local default_library="$steam_path/steamapps/common/Kerbal Space Program/GameData"
    if [ -d "$default_library" ]; then
        echo "$default_library"
        return
    fi
    
    # Check for additional library folders
    local library_file="$steam_path/steamapps/libraryfolders.vdf"
    if [ -f "$library_file" ]; then
        # Extract paths from libraryfolders.vdf using grep and sed
        local library_paths=$(grep -E '"path"' "$library_file" | sed -E 's/.*"path"[[:space:]]*"([^"]+)".*/\1/')
        
        for lib_path in $library_paths; do
            # Replace escaped backslashes with forward slashes for Mac
            lib_path=$(echo "$lib_path" | sed 's/\\\\/\//g')
            
            local ksp_path="$lib_path/steamapps/common/Kerbal Space Program/GameData"
            if [ -d "$ksp_path" ]; then
                echo "$ksp_path"
                return
            fi
        done
    fi
    
    # If we can't find KSP, use the path from config
    echo "$CONFIG_LOCAL_PATH"
}

# Function to check if a path should be excluded
should_exclude() {
    local path="$1"
    
    for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
        if [[ "$path" == *"/$exclude_dir/"* || "$path" == *"/$exclude_dir" ]]; then
            return 0  # True, should exclude
        fi
    done
    
    return 1  # False, should not exclude
}

# Function to sync a directory
sync_directory() {
    local source="$1"
    local destination="$2"
    
    # Create destination if it doesn't exist
    if [ ! -d "$destination" ]; then
        mkdir -p "$destination"
        write_log "Created directory: $destination"
    fi
    
    # Build exclude options for rsync
    RSYNC_EXCLUDE=""
    for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
        RSYNC_EXCLUDE="$RSYNC_EXCLUDE --exclude=/$exclude_dir/ --exclude=/$exclude_dir"
    done
    
    # Add standard excludes
    RSYNC_EXCLUDE="$RSYNC_EXCLUDE --exclude=.DS_Store --exclude=._.DS_Store --exclude=thumbs.db"
    
    # Sync using rsync
    rsync -av --delete $RSYNC_EXCLUDE "$source/" "$destination/" | while read line; do
        # Log only the files being transferred, not the directories
        if [[ "$line" == *"/"* && ! "$line" == *"/"*"/" ]]; then
            # Skip rsync summary lines
            if [[ ! "$line" == "sending"* && ! "$line" == "sent"* && ! "$line" == "total"* && ! "$line" == "building"* ]]; then
                write_log "$line"
            fi
        fi
    done
}

# Main execution
main() {
    write_log "Starting KSP mod synchronization"
    
    # Check if NFS share is mounted
    if ! mount | grep -q "$MOUNT_POINT"; then
        write_log "Mounting NFS share..."
        sudo mkdir -p "$MOUNT_POINT"
        sudo mount -t nfs "$NFS_SERVER:$NFS_SHARE" "$MOUNT_POINT"
        if [ $? -ne 0 ]; then
            write_log "ERROR: Failed to mount NFS share"
            exit 1
        fi
        write_log "NFS share mounted successfully"
    fi
    
    # Create logs directory if it doesn't exist
    mkdir -p "$MOUNT_POINT/logs"
    
    # Find KSP installation
    LOCAL_PATH=$(find_ksp_path)
    write_log "Using KSP GameData path: $LOCAL_PATH"
    
    # Check if local GameData directory exists
    if [ ! -d "$LOCAL_PATH" ]; then
        write_log "ERROR: Cannot access local GameData directory at $LOCAL_PATH"
        exit 1
    fi
    
    # Ensure remote directory exists
    mkdir -p "$REMOTE_PATH"
    
    # First sync from local to remote (upload new mods)
    write_log "Syncing from local to remote..."
    sync_directory "$LOCAL_PATH" "$REMOTE_PATH"
    
    # Then sync from remote to local (download mods from other machines)
    write_log "Syncing from remote to local..."
    sync_directory "$REMOTE_PATH" "$LOCAL_PATH"
    
    write_log "Synchronization completed successfully"
}

# Run the main function
main
