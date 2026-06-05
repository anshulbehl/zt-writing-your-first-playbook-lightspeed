#!/bin/bash

# Setup script for vscode VM
# The devtools-ansible image already has code-server pre-installed
# This script configures and starts code-server

set -e

# Create ansible-files directory accessible to rhel user
mkdir -p /home/rhel/ansible-files
chown -R rhel:rhel /home/rhel/ansible-files

# Stop code-server if already running
systemctl stop code-server || true

# Backup existing config if present
[ -f /home/rhel/.config/code-server/config.yaml ] && \
  mv /home/rhel/.config/code-server/config.yaml /home/rhel/.config/code-server/config.bk.yaml || true

# Create code-server configuration
mkdir -p /home/rhel/.config/code-server
cat > /home/rhel/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF
chown -R rhel:rhel /home/rhel/.config/code-server

# Start code-server service
systemctl start code-server
systemctl enable code-server

echo "VSCode VM setup complete"
