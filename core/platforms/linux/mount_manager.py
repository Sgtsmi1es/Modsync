#!/usr/bin/env python3
"""
mount_manager.py - Manages NFS mounts on Linux
"""
import os
import subprocess
import logging

class LinuxMountManager:
    """Manages NFS mounts on Linux systems"""
    
    def __init__(self, config):
        self.logger = logging.getLogger('modsync.linux.mount_manager')
        self.config = config
        self.server = config['server']['nfs_server']
        self.share = config['server']['nfs_share']
        self.mount_point = config['server']['mount_point']
    
    def is_mounted(self):
        """Check if the NFS share is already mounted"""
        try:
            result = subprocess.run(['mount'], capture_output=True, text=True)
            return f"{self.server}:{self.share}" in result.stdout
        except Exception as e:
            self.logger.error(f"Error checking mount status: {e}")
            return False
    
    def mount(self):
        """Mount the NFS share"""
        if self.is_mounted():
            self.logger.info(f"NFS share {self.server}:{self.share} is already mounted")
            return True
        
        try:
            # Ensure mount point exists
            os.makedirs(self.mount_point, exist_ok=True)
            
            # Mount the NFS share
            cmd = ['sudo', 'mount', '-t', 'nfs', f"{self.server}:{self.share}", self.mount_point]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully mounted {self.server}:{self.share} to {self.mount_point}")
                return True
            else:
                self.logger.error(f"Failed to mount NFS share: {result.stderr}")
                return False
        
        except Exception as e:
            self.logger.error(f"Error mounting NFS share: {e}")
            return False
    
    def unmount(self):
        """Unmount the NFS share"""
        if not self.is_mounted():
            self.logger.info(f"NFS share {self.server}:{self.share} is not mounted")
            return True
        
        try:
            cmd = ['sudo', 'umount', self.mount_point]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully unmounted {self.mount_point}")
                return True
            else:
                self.logger.error(f"Failed to unmount NFS share: {result.stderr}")
                return False
        
        except Exception as e:
            self.logger.error(f"Error unmounting NFS share: {e}")
            return False
    
    def ensure_mounted(self):
        """Ensure the NFS share is mounted, mounting it if necessary"""
        if not self.is_mounted():
            return self.mount()
        return True

if __name__ == "__main__":
    # Setup basic logging
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Example config
    config = {
        'server': {
            'nfs_server': '10.10.1.12',
            'nfs_share': '/mnt/user/bridger_storage',
            'mount_point': '/mnt/bridger_storage'
        }
    }
    
    # Example usage
    mount_manager = LinuxMountManager(config)
    mount_manager.ensure_mounted()
