#!/usr/bin/env python3
"""
file_monitor.py - Monitors directories for file changes
"""
import os
import time
import json
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class FileChangeHandler(FileSystemEventHandler):
    """Handles file system events and logs changes"""
    
    def __init__(self, sync_queue, config):
        self.sync_queue = sync_queue
        self.config = config
        self.logger = logging.getLogger('modsync.file_monitor')
    
    def on_modified(self, event):
        if event.is_directory:
            return
        self.logger.info(f"File modified: {event.src_path}")
        self.sync_queue.put(('modified', event.src_path))
    
    def on_created(self, event):
        self.logger.info(f"File created: {event.src_path}")
        self.sync_queue.put(('created', event.src_path))
    
    def on_deleted(self, event):
        self.logger.info(f"File deleted: {event.src_path}")
        self.sync_queue.put(('deleted', event.src_path))
    
    def on_moved(self, event):
        self.logger.info(f"File moved from {event.src_path} to {event.dest_path}")
        self.sync_queue.put(('moved', (event.src_path, event.dest_path)))


class FileMonitor:
    """Monitors directories for changes and triggers sync events"""
    
    def __init__(self, config_path):
        self.logger = logging.getLogger('modsync.file_monitor')
        self.config = self._load_config(config_path)
        self.observers = []
        self.sync_queue = []  # This would be replaced with a proper queue in a multi-threaded app
    
    def _load_config(self, config_path):
        """Load configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.logger.error(f"Error loading config: {e}")
            return {}
    
    def start_monitoring(self):
        """Start monitoring all configured directories"""
        for dir_config in self.config.get('sync_directories', []):
            local_path = dir_config.get('local_path')
            if not os.path.exists(local_path):
                self.logger.warning(f"Directory does not exist: {local_path}")
                continue
            
            event_handler = FileChangeHandler(self.sync_queue, self.config)
            observer = Observer()
            observer.schedule(event_handler, local_path, recursive=True)
            observer.start()
            self.observers.append(observer)
            self.logger.info(f"Started monitoring: {local_path}")
    
    def stop_monitoring(self):
        """Stop all directory monitoring"""
        for observer in self.observers:
            observer.stop()
        
        for observer in self.observers:
            observer.join()
        
        self.logger.info("Stopped all directory monitoring")

if __name__ == "__main__":
    # Setup basic logging
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Example usage
    monitor = FileMonitor('../config/sync_config.json')
    try:
        monitor.start_monitoring()
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        monitor.stop_monitoring()
