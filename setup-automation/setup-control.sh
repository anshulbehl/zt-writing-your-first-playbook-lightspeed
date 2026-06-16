#!/bin/bash
#
# Setup script for control node
# Purpose: Configure code-server and create Ansible workspace
# The devtools-ansible image already has code-server pre-installed
#

echo "Setting up control node..."

# Create network diagnostics log
echo "=== Network Setup Diagnostics ===" > /home/rhel/network-debug.txt
echo "Date: $(date)" >> /home/rhel/network-debug.txt
echo "" >> /home/rhel/network-debug.txt
echo "Control IP Address:" >> /home/rhel/network-debug.txt
ip addr show eth0 | grep "inet " >> /home/rhel/network-debug.txt
echo "" >> /home/rhel/network-debug.txt
echo "Routing Table:" >> /home/rhel/network-debug.txt
ip route show >> /home/rhel/network-debug.txt
echo "" >> /home/rhel/network-debug.txt
echo "DNS Resolution Test:" >> /home/rhel/network-debug.txt
getent hosts node1 >> /home/rhel/network-debug.txt 2>&1 || echo "node1 resolution FAILED" >> /home/rhel/network-debug.txt
getent hosts node2 >> /home/rhel/network-debug.txt 2>&1 || echo "node2 resolution FAILED" >> /home/rhel/network-debug.txt
getent hosts node3 >> /home/rhel/network-debug.txt 2>&1 || echo "node3 resolution FAILED" >> /home/rhel/network-debug.txt
echo "" >> /home/rhel/network-debug.txt
echo "Gateway reachability:" >> /home/rhel/network-debug.txt
ping -c 2 10.0.2.1 >> /home/rhel/network-debug.txt 2>&1 || echo "Gateway 10.0.2.1 not reachable" >> /home/rhel/network-debug.txt
echo "" >> /home/rhel/network-debug.txt
chown rhel:rhel /home/rhel/network-debug.txt

# Node /etc/hosts entries are configured by setup-automation/main.yml
# using each VM's actual IP from Ansible facts (getent can return duplicate IPs in CNV DNS)

# Configure SSH defaults for the rhel user
mkdir -p /home/rhel/.ssh
chmod 700 /home/rhel/.ssh
cat > /home/rhel/.ssh/config << 'EOF'
Host node1 node2 node3
    User rhel
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /home/rhel/.ssh/config
chown -R rhel:rhel /home/rhel/.ssh

# Create ansible-files directory structure
mkdir -p /home/rhel/ansible-files/templates
chown -R rhel:rhel /home/rhel/ansible-files

# Create ansible.cfg
cat > /home/rhel/ansible-files/ansible.cfg << 'EOF'
[defaults]
inventory = inventory
host_key_checking = False

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10
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

[all:vars]
ansible_user=rhel
ansible_password=ansible123!
ansible_connection=ssh
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

# Configure Ansible Lightspeed to use LiteMaaS endpoint
# MUST happen BEFORE code-server starts — the extension runs migration on first
# activation and sets a flag that prevents re-migration. If settings.json is
# written after code-server starts, the migration already ran with no config
# and defaults to WCA (which triggers a Red Hat OAuth redirect).
LITEMAAS_BASE_URL="https://maas-rhdp.apps.maas.redhatworkshops.io"
LITEMAAS_MODEL_NAME="openai/deepseek-r1-distill-qwen-14b"

if [ -n "${LITEMAAS_API_KEY}" ]; then
  echo "Configuring Ansible Lightspeed with LiteMaaS endpoint..."

  # code-server user-level settings
  mkdir -p /home/rhel/.local/share/code-server/User
  cat > /home/rhel/.local/share/code-server/User/settings.json << EOSETTINGS
{
  "ansible.lightspeed.enabled": true,
  "ansible.lightspeed.provider": "rhcustom",
  "ansible.lightspeed.apiEndpoint": "${LITEMAAS_BASE_URL}",
  "ansible.lightspeed.apiKey": "${LITEMAAS_API_KEY}",
  "ansible.lightspeed.modelName": "${LITEMAAS_MODEL_NAME}"
}
EOSETTINGS
  chown -R rhel:rhel /home/rhel/.local/share/code-server

  # Workspace-level settings (fallback)
  mkdir -p /home/rhel/ansible-files/.vscode
  cat > /home/rhel/ansible-files/.vscode/settings.json << EOSETTINGS
{
  "ansible.lightspeed.enabled": true,
  "ansible.lightspeed.provider": "rhcustom",
  "ansible.lightspeed.apiEndpoint": "${LITEMAAS_BASE_URL}",
  "ansible.lightspeed.apiKey": "${LITEMAAS_API_KEY}",
  "ansible.lightspeed.modelName": "${LITEMAAS_MODEL_NAME}"
}
EOSETTINGS
  chown -R rhel:rhel /home/rhel/ansible-files/.vscode

  echo "Ansible Lightspeed configured: ${LITEMAAS_BASE_URL} (model: ${LITEMAAS_MODEL_NAME})"
else
  echo "WARNING: LITEMAAS_API_KEY not set — Ansible Lightspeed will not be configured"
fi

# Configure and start code-server (VS Code in browser)
# Settings.json must already exist before this point so the Ansible extension
# picks up the rhcustom provider config on first activation.
echo "Configuring code-server..."

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

echo "Control node setup complete (ansible-files + code-server + lightspeed)"
echo "Node IP mappings:"
grep -E "node[123]" /etc/hosts || echo "No nodes found in /etc/hosts"
