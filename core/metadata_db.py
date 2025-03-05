#!/usr/bin/env python3
"""
metadata_db.py - Tracks file metadata for synchronization
"""
import os
import json
import logging
import sqlite3
from datetime import datetime

class MetadataDB:
    """Manages file metadata for tracking sync state"""
    
    def __init__(self, db_path):
        self.logger = logging.getLogger('modsync.metadata_db')
        self.db_path = db_path
        self._init_db()
    
    def _init_db(self):
        """Initialize the SQLite database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Create files table if it doesn't exist
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE,
                modified_time REAL,
                size INTEGER,
                last_synced REAL,
                sync_status TEXT,
                checksum TEXT
            )
            ''')
            
            conn.commit()
            conn.close()
            self.logger.info(f"Initialized metadata database at {self.db_path}")
        
        except Exception as e:
            self.logger.error(f"Error initializing database: {e}")
    
    def update_file_metadata(self, file_path):
        """Update metadata for a file"""
        try:
            if not os.path.exists(file_path):
                self.delete_file_metadata(file_path)
                return
            
            stat = os.stat(file_path)
            modified_time = stat.st_mtime
            size = stat.st_size
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Check if file exists in DB
            cursor.execute("SELECT * FROM files WHERE path = ?", (file_path,))
            existing = cursor.fetchone()
            
            if existing:
                cursor.execute('''
                UPDATE files 
                SET modified_time = ?, size = ?, last_synced = ?, sync_status = ?
                WHERE path = ?
                ''', (modified_time, size, time.time(), 'synced', file_path))
            else:
                cursor.execute('''
                INSERT INTO files (path, modified_time, size, last_synced, sync_status)
                VALUES (?, ?, ?, ?, ?)
                ''', (file_path, modified_time, size, time.time(), 'synced'))
            
            conn.commit()
            conn.close()
            self.logger.debug(f"Updated metadata for {file_path}")
        
        except Exception as e:
            self.logger.error(f"Error updating metadata for {file_path}: {e}")
    
    def delete_file_metadata(self, file_path):
        """Delete metadata for a file"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM files WHERE path = ?", (file_path,))
            
            conn.commit()
            conn.close()
            self.logger.debug(f"Deleted metadata for {file_path}")
        
        except Exception as e:
            self.logger.error(f"Error deleting metadata for {file_path}: {e}")
    
    def get_file_metadata(self, file_path):
        """Get metadata for a file"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("SELECT * FROM files WHERE path = ?", (file_path,))
            row = cursor.fetchone()
            
            conn.close()
            
            if row:
                return {
                    'id': row[0],
                    'path': row[1],
                    'modified_time': row[2],
                    'size': row[3],
                    'last_synced': row[4],
                    'sync_status': row[5],
                    'checksum': row[6]
                }
            return None
        
        except Exception as e:
            self.logger.error(f"Error getting metadata for {file_path}: {e}")
            return None
    
    def needs_sync(self, file_path):
        """Check if a file needs to be synced"""
        if not os.path.exists(file_path):
            return False
        
        metadata = self.get_file_metadata(file_path)
        if not metadata:
            return True
        
        stat = os.stat(file_path)
        return stat.st_mtime > metadata['modified_time'] or stat.st_size != metadata['size']

if __name__ == "__main__":
    # Setup basic logging
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Example usage
    db = MetadataDB('sync_metadata.db')
    test_file = 'test_file.txt'
    
    # Create a test file
    with open(test_file, 'w') as f:
        f.write('Test content')
    
    # Update metadata
    db.update_file_metadata(test_file)
    
    # Check if it needs sync
    print(f"Needs sync: {db.needs_sync(test_file)}")
    
    # Modify the file
    time.sleep(1)  # Ensure modified time changes
    with open(test_file, 'w') as f:
        f.write('Modified content')
    
    # Check again
    print(f"Needs sync after modification: {db.needs_sync(test_file)}")
    
    # Clean up
    os.remove(test_file)
