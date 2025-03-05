#!/bin/bash
# Install script for KSP Mod Sync Log Server

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Install dependencies
apt-get update
apt-get install -y python3 python3-pip sqlite3

# Install Python packages
pip3 install flask gunicorn

# Create service user
useradd -r -s /bin/false modsync || true

# Create directories
mkdir -p /opt/modsync/logs
mkdir -p /var/log/modsync

# Copy files
cp log_server.py /opt/modsync/
chmod +x /opt/modsync/log_server.py

# Create systemd service
cat > /etc/systemd/system/modsync-log.service << EOF
[Unit]
Description=KSP Mod Sync Log Server
After=network.target

[Service]
User=modsync
WorkingDirectory=/opt/modsync
ExecStart=/usr/bin/gunicorn --workers 4 --bind 0.0.0.0:5000 log_server:app
Restart=always
StandardOutput=append:/var/log/modsync/server.log
StandardError=append:/var/log/modsync/server.log

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chown -R modsync:modsync /opt/modsync
chown -R modsync:modsync /var/log/modsync

# Enable and start service
systemctl daemon-reload
systemctl enable modsync-log
systemctl start modsync-log

echo "KSP Mod Sync Log Server installed successfully!"
echo "API is available at http://$(hostname -I | awk '{print $1}'):5000/api/logs"
echo "Log files are in /opt/modsync/logs/" 