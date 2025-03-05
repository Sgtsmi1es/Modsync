#!/usr/bin/env python3
"""
sync_now.py - Manual synchronization script
"""
import os
import sys
import json
import logging
import argparse

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from core.sync_engine import SyncEngine
from core.platforms.linux.mount_manager import LinuxMountManager

def main():
    parser = argparse.ArgumentParser(description='Manually synchronize files')
    parser.add_argument('--config', default='../config/sync_config.json',
                        help='Path to configuration file')
    parser.add_argument('--log-level', default='INFO',
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                        help='Set the logging level')
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger('modsync.sync_now')
    
    # Load configuration
    config_path = os.path.abspath(args.config)
    if not os.path.exists(config_path):
        logger.error(f"Configuration file not found: {config_path}")
        return 1
    
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
    except Exception as e:
        logger.error(f"Error loading configuration: {e}")
        return 1
    
    # Ensure NFS share is mounted
    mount_manager = LinuxMountManager(config)
    if not mount_manager.ensure_mounted():
        logger.error("Failed to mount NFS share. Aborting sync.")
        return 1
    
    # Perform synchronization
    sync_engine = SyncEngine(config_path)
    sync_engine.full_sync()
    
    logger.info("Synchronization completed successfully")
    return 0

if __name__ == "__main__":
    sys.exit(main())
