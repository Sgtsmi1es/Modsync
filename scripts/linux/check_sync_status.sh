#!/bin/bash
#
# Checks and reports on the status of KSP mod synchronization.

# Exit on error
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../../config/sync_config.json"
MOUNT_POINT=$(jq -r '.server.mount_point' "$CONFIG_PATH")
REMOTE_PATH="$MOUNT_POINT/$(jq -r '.sync_directories[0].remote_path' "$CONFIG_PATH")"
LOG_FILE="$MOUNT_POINT/logs/modsync.log"

# Function to display sync status
display_status() {
    echo "=== KSP Mod Sync Status ==="
    echo
    
    # Check if log file exists
    if [ -f "$LOG_FILE" ]; then
        echo "Last 10 sync events:"
        grep -E '\[(Windows|Mac)\]' "$LOG_FILE" | tail -n 10
        echo
        
        # Count syncs by platform
        WINDOWS_SYNCS=$(grep -c '\[Windows\]' "$LOG_FILE" || true)
        MAC_SYNCS=$(grep -c '\[Mac\]' "$LOG_FILE" || true)
        echo "Total syncs by platform:"
        echo "  Windows: $WINDOWS_SYNCS"
        echo "  Mac: $MAC_SYNCS"
        echo
        
        # Last sync time by platform
        LAST_WINDOWS=$(grep '\[Windows\]' "$LOG_FILE" | tail -n 1 | cut -d']' -f1 | tr -d '[' || echo "Never")
        LAST_MAC=$(grep '\[Mac\]' "$LOG_FILE" | tail -n 1 | cut -d']' -f1 | tr -d '[' || echo "Never")
        echo "Last sync time by platform:"
        echo "  Windows: $LAST_WINDOWS"
        echo "  Mac: $LAST_MAC"
        echo
    else
        echo "No sync log found. Sync may not have run yet."
        echo
    fi
    
    # Check mod directory size
    if [ -d "$REMOTE_PATH" ]; then
        MOD_SIZE=$(du -sh "$REMOTE_PATH" | cut -f1)
        MOD_COUNT=$(find "$REMOTE_PATH" -type d -mindepth 1 -maxdepth 1 | wc -l)
        echo "Mod directory: $REMOTE_PATH"
        echo "Total size: $MOD_SIZE"
        echo "Number of mod directories: $MOD_COUNT"
        echo
        echo "Top 10 largest mods:"
        find "$REMOTE_PATH" -type d -mindepth 1 -maxdepth 1 -print0 | xargs -0 du -sh | sort -hr | head -n 10
    else
        echo "Mod directory not found or not accessible."
    fi
}

# Main execution
display_status
