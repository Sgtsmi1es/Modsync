#!/usr/bin/env python3
"""
sync_engine.py - Core synchronization logic
"""
import os
import shutil
import json
import logging
import time
from datetime import datetime

class SyncEngine:
    """Handles file synchronization between local and remote directories"""
    
    def __init__(self, config_path):
        self.logger = logging.getLogger('modsync.sync_engine')
        self.config = self._load_config(config_path)
        self.metadata_db = {}  # This would be replaced with a proper database
    
    def _load_config(self, config_path):
        """Load configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.logger.error(f"Error loading config: {e}")
            return {}
    
    def _get_remote_path(self, local_path):
        """Convert a local path to its corresponding remote path"""
        for dir_config in self.config.get('sync_directories', []):
            local_dir = dir_config.get('local_path')
            if local_path.startswith(local_dir):
                relative_path = os.path.relpath(local_path, local_dir)
                remote_dir = os.path.join(
                    self.config['server']['mount_point'],
                    dir_config.get('remote_path')
                )
                return os.path.join(remote_dir, relative_path)
        return None
    
    def _should_sync_file(self, file_path):
        """Check if a file should be synced based on include/exclude patterns"""
        # This is a simplified implementation
        filename = os.path.basename(file_path)
        
        # Check against exclude patterns
        for dir_config in self.config.get('sync_directories', []):
            for pattern in dir_config.get('exclude_patterns', []):
                if pattern.startswith('*'):
                    if filename.endswith(pattern[1:]):
                        return False
                elif pattern.endswith('*'):
                    if filename.startswith(pattern[:-1]):
                        return False
                elif pattern == filename:
                    return False
        
        return True
    
    def sync_file(self, action, file_path, dest_path=None):
        """Synchronize a single file based on the action"""
        if not self._should_sync_file(file_path):
            self.logger.debug(f"Skipping excluded file: {file_path}")
            return
        
        remote_path = dest_path or self._get_remote_path(file_path)
        if not remote_path:
            self.logger.warning(f"Could not determine remote path for: {file_path}")
            return
        
        try:
            if action == 'created' or action == 'modified':
                # Ensure the directory exists
                os.makedirs(os.path.dirname(remote_path), exist_ok=True)
                # Copy the file
                shutil.copy2(file_path, remote_path)
                self.logger.info(f"Synced {action} file: {file_path} -> {remote_path}")
            
            elif action == 'deleted':
                if os.path.exists(remote_path):
                    os.remove(remote_path)
                    self.logger.info(f"Deleted remote file: {remote_path}")
            
            elif action == 'moved':
                if dest_path:
                    remote_dest = self._get_remote_path(dest_path)
                    if remote_dest:
                        # Ensure the directory exists
                        os.makedirs(os.path.dirname(remote_dest), exist_ok=True)
                        # Move the file
                        shutil.move(remote_path, remote_dest)
                        self.logger.info(f"Moved remote file: {remote_path} -> {remote_dest}")
        
        except Exception as e:
            self.logger.error(f"Error syncing file {file_path}: {e}")
    
    def sync_directory(self, local_dir, remote_dir):
        """Synchronize an entire directory"""
        self.logger.info(f"Starting directory sync: {local_dir} -> {remote_dir}")
        
        # Ensure remote directory exists
        os.makedirs(remote_dir, exist_ok=True)
        
        # Walk through the local directory
        for root, dirs, files in os.walk(local_dir):
            # Create corresponding remote directories
            for dir_name in dirs:
                local_path = os.path.join(root, dir_name)
                relative_path = os.path.relpath(local_path, local_dir)
                remote_path = os.path.join(remote_dir, relative_path)
                os.makedirs(remote_path, exist_ok=True)
            
            # Sync files
            for file_name in files:
                local_path = os.path.join(root, file_name)
                if self._should_sync_file(local_path):
                    relative_path = os.path.relpath(local_path, local_dir)
                    remote_path = os.path.join(remote_dir, relative_path)
                    self.sync_file('created', local_path, remote_path)
    
    def full_sync(self):
        """Perform a full synchronization of all configured directories"""
        self.logger.info("Starting full synchronization")
        
        for dir_config in self.config.get('sync_directories', []):
            local_path = dir_config.get('local_path')
            remote_path = os.path.join(
                self.config['server']['mount_point'],
                dir_config.get('remote_path')
            )
            
            if os.path.exists(local_path):
                self.sync_directory(local_path, remote_path)
            else:
                self.logger.warning(f"Local directory does not exist: {local_path}")
        
        self.logger.info("Full synchronization completed")

if __name__ == "__main__":
    # Setup basic logging
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Example usage
    sync_engine = SyncEngine('../config/sync_config.json')
    sync_engine.full_sync()

