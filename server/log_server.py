#!/usr/bin/env python3
"""
Log Server for KSP Mod Sync
Provides a REST API for logging and generates text log files from the database.
"""

from flask import Flask, request, jsonify
import sqlite3
import os
import time
from datetime import datetime
import threading

app = Flask(__name__)

# Configuration
DATABASE_FILE = "modsync_logs.db"
LOG_OUTPUT_DIR = "logs"
LOG_FILE = os.path.join(LOG_OUTPUT_DIR, "modsync.log")
LOG_ROTATION_INTERVAL = 86400  # 24 hours in seconds

# Ensure log directory exists
os.makedirs(LOG_OUTPUT_DIR, exist_ok=True)

# Initialize database
def init_db():
    conn = sqlite3.connect(DATABASE_FILE)
    cursor = conn.cursor()
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        computer TEXT,
        process_id INTEGER,
        session_id TEXT,
        platform TEXT,
        level TEXT,
        message TEXT,
        processed INTEGER DEFAULT 0
    )
    ''')
    conn.commit()
    conn.close()

init_db()

# API endpoint to receive logs
@app.route('/api/logs', methods=['POST'])
def add_log():
    try:
        data = request.json
        
        # Validate required fields
        required_fields = ['timestamp', 'computer', 'platform', 'message']
        for field in required_fields:
            if field not in data:
                return jsonify({"error": f"Missing required field: {field}"}), 400
        
        # Connect to database
        conn = sqlite3.connect(DATABASE_FILE)
        cursor = conn.cursor()
        
        # Insert log entry
        cursor.execute('''
        INSERT INTO logs (timestamp, computer, process_id, session_id, platform, level, message)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            data.get('timestamp'),
            data.get('computer'),
            data.get('process_id', 0),
            data.get('session_id', ''),
            data.get('platform'),
            data.get('level', 'INFO'),
            data.get('message')
        ))
        
        conn.commit()
        conn.close()
        
        return jsonify({"status": "success"}), 201
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Function to process logs and write to text file
def process_logs():
    while True:
        try:
            conn = sqlite3.connect(DATABASE_FILE)
            cursor = conn.cursor()
            
            # Get unprocessed logs
            cursor.execute('''
            SELECT id, timestamp, computer, process_id, session_id, platform, level, message
            FROM logs
            WHERE processed = 0
            ORDER BY timestamp
            ''')
            
            logs = cursor.fetchall()
            
            if logs:
                with open(LOG_FILE, 'a') as f:
                    for log in logs:
                        log_id, timestamp, computer, process_id, session_id, platform, level, message = log
                        log_entry = f"[{timestamp}] [{computer}:{process_id}:{session_id}] [{platform}] [{level}] {message}\n"
                        f.write(log_entry)
                        
                        # Mark as processed
                        cursor.execute('UPDATE logs SET processed = 1 WHERE id = ?', (log_id,))
                
                conn.commit()
            
            conn.close()
            
            # Sleep for a short time before checking again
            time.sleep(5)
            
        except Exception as e:
            print(f"Error processing logs: {e}")
            time.sleep(30)  # Longer sleep on error

# Function to rotate log files
def rotate_logs():
    while True:
        try:
            if os.path.exists(LOG_FILE):
                # Create a timestamp for the rotated file
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                rotated_file = f"{LOG_FILE}.{timestamp}"
                
                # Rename current log file
                os.rename(LOG_FILE, rotated_file)
                
                # Create a new empty log file
                with open(LOG_FILE, 'w') as f:
                    f.write(f"Log started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                
                print(f"Rotated log file to {rotated_file}")
            
            # Sleep for the rotation interval
            time.sleep(LOG_ROTATION_INTERVAL)
            
        except Exception as e:
            print(f"Error rotating logs: {e}")
            time.sleep(3600)  # Retry in an hour

# Start background threads
log_processor = threading.Thread(target=process_logs, daemon=True)
log_processor.start()

log_rotator = threading.Thread(target=rotate_logs, daemon=True)
log_rotator.start()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000) 