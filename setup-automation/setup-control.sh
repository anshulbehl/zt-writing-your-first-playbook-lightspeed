#!/bin/bash

# Setup script for control node
# Minimal setup - just install Ansible and create directories

set -e

# Create rhel user directories
mkdir -p /home/rhel/ansible-files
chown -R rhel:rhel /home/rhel/ansible-files

# Create ansible configuration for rhel user
cat > /home/rhel/.ansible.cfg << 'EOF'
[defaults]
inventory = /home/rhel/ansible-files/inventory
host_key_checking = False
EOF
chown rhel:rhel /home/rhel/.ansible.cfg

echo "Control node setup complete"
