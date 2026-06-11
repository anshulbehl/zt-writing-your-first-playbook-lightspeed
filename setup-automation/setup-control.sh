#!/bin/bash
#
# Setup script for control node
# Purpose: Install Ansible, code-server, and create workspace
# This VM runs both VS Code (code-server) and ansible-navigator
#
set -e  # Exit immediately if any command fails

echo "Setting up control node..."

# Register to RHDP Satellite for package installation
echo "Registering to Red Hat Satellite..."
subscription-manager register \
  --org="${SATELLITE_ORG}" \
  --activationkey="${SATELLITE_ACTIVATIONKEY}"

# Install required packages
echo "Installing ansible-navigator and podman..."
dnf install -y \
  ansible-navigator \
  podman \
  git

# Install code-server (VS Code in browser)
echo "Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh

# Create ansible-files directory structure
mkdir -p /home/rhel/ansible-files/templates
chown -R rhel:rhel /home/rhel/ansible-files

# Create ansible.cfg
cat > /home/rhel/ansible-files/ansible.cfg << 'EOF'
[defaults]
inventory = inventory
host_key_checking = False
EOF

# Create ansible-navigator.yml
cat > /home/rhel/ansible-files/ansible-navigator.yml << 'EOF'
---
ansible-navigator:
  ansible:
    inventory:
      entries:
      - /home/rhel/ansible-files/inventory
  execution-environment:
    container-engine: podman
    container-options:
      - "--network=host"
    enabled: true
    image: quay.io/acme_corp/first_playbook_ee:latest
    pull:
      policy: missing
  logging:
    level: debug
    file: /home/rhel/.logs/ansible-navigator.log
  mode: stdout
  playbook-artifact:
    save-as: /home/rhel/.logs/{playbook_name}-artifact-{time_stamp}.json
EOF

# Create inventory
cat > /home/rhel/ansible-files/inventory << 'EOF'
[web]
node1
node2

[database]
node3

[nodes:children]
web
database
EOF

# Create motd.j2 template
cat > /home/rhel/ansible-files/templates/motd.j2 << 'EOF'
Welcome to {{ ansible_hostname }}.
OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
Architecture: {{ ansible_architecture }}
EOF

# Create logs directory for ansible-navigator
mkdir -p /home/rhel/.logs

# Set ownership to rhel user for all created files
chown -R rhel:rhel /home/rhel/ansible-files
chown -R rhel:rhel /home/rhel/.logs

# Configure code-server (VS Code in browser)
echo "Configuring code-server..."

# Stop code-server if already running
systemctl stop code-server@rhel || true

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

# Start code-server service as rhel user
systemctl enable --now code-server@rhel

# Install Ansible VS Code extension (for Lightspeed)
echo "Installing Ansible VS Code extension..."
su - rhel -c "code-server --install-extension redhat.ansible"

echo "Control node setup complete (ansible-navigator + code-server)"
