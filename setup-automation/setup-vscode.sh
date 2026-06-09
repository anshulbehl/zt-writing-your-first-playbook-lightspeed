#!/bin/bash
#
# Setup script for vscode VM
# Purpose: Configure code-server, LiteLLM proxy for Ansible Lightspeed, and SSHFS mount
# This VM runs the browser-based VS Code interface where students edit playbooks
# Files are mounted from control VM via SSHFS for real-time sync
#
set -e  # Exit immediately if any command fails

# ─── Helper Functions ────────────────────────────────────────────────────────

# Function: wait_for_service
# Purpose: Wait for a systemd service to become active
# Args: $1=service name, $2=max wait time in seconds (default 60)
# Returns: 0 if service active, 1 if timeout
wait_for_service() {
    local service=$1
    local max_wait=${2:-60}
    local elapsed=0

    echo "[setup-vscode] Waiting for $service to be active..."

    # Poll every 2 seconds until service is active or timeout
    while [ $elapsed -lt $max_wait ]; do
        if systemctl is-active --quiet "$service"; then
            echo "[setup-vscode] $service is active"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    # Service failed to start - dump status for debugging
    echo "[setup-vscode] ERROR: $service failed to start within ${max_wait}s"
    systemctl status "$service" --no-pager || true
    return 1
}

# Function: wait_for_http
# Purpose: Wait for HTTP endpoint to respond
# Args: $1=URL, $2=max wait time in seconds (default 60)
# Returns: 0 if URL responds, 1 if timeout
wait_for_http() {
    local url=$1
    local max_wait=${2:-60}
    local elapsed=0

    echo "[setup-vscode] Waiting for $url to respond..."

    # Poll every 2 seconds until URL responds or timeout
    while [ $elapsed -lt $max_wait ]; do
        # curl -s=silent, -f=fail on HTTP error
        if curl -sf "$url" >/dev/null 2>&1; then
            echo "[setup-vscode] $url is responding"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "[setup-vscode] ERROR: $url not responding within ${max_wait}s"
    return 1
}

# ─── Mount ansible-files from control VM via SSHFS ──────────────────────────

echo "[setup-vscode] Setting up SSHFS mount to control VM..."
# Why SSHFS:
#   - Students edit files in VS Code (this VM)
#   - Students run ansible-navigator in Control terminal (control VM)
#   - Files must be shared between VMs - single source of truth
#   - SSHFS mounts control VM's /home/rhel/ansible-files here
#   - Edits in VS Code immediately visible to ansible-navigator

echo "[setup-vscode] Installing SSHFS"
# Install fuse-sshfs package for SSHFS mounting
# Try dnf first (RHEL 8+), fall back to yum (RHEL 7)
dnf install -y fuse-sshfs || yum install -y fuse-sshfs

echo "[setup-vscode] Creating mount point"
# Create directory that will become the SSHFS mount point
mkdir -p /home/rhel/ansible-files

echo "[setup-vscode] Configuring SSH for passwordless access to control VM"
# Set up SSH directory with correct permissions
mkdir -p /home/rhel/.ssh
chmod 700 /home/rhel/.ssh

# Generate SSH key pair if it doesn't already exist
# -t rsa = RSA algorithm
# -b 2048 = 2048-bit key size
# -N "" = no passphrase (required for automated mounting)
# -f = output file path
if [ ! -f /home/rhel/.ssh/id_rsa ]; then
    echo "[setup-vscode] Generating SSH key pair"
    su - rhel -c 'ssh-keygen -t rsa -b 2048 -N "" -f /home/rhel/.ssh/id_rsa'
else
    echo "[setup-vscode] SSH key already exists, skipping generation"
fi

# Create SSH config for control VM connection
# StrictHostKeyChecking no = don't prompt about host key
# UserKnownHostsFile /dev/null = don't save host keys (lab environment)
cat > /home/rhel/.ssh/config << 'EOF'
Host control
    HostName control
    User rhel
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /home/rhel/.ssh/config
chown -R rhel:rhel /home/rhel/.ssh

echo "[setup-vscode] Waiting for control VM to complete setup..."
# Wait for control VM to:
#   1. Be SSH-accessible
#   2. Have /home/rhel/ansible-files directory created
#   3. Have inventory file downloaded (indicates setup-control.sh completed)
# Retry for up to 5 minutes (60 attempts * 5 seconds)
for attempt in {1..60}; do
    # ConnectTimeout prevents hanging if control VM is not yet up
    if ssh -o ConnectTimeout=5 rhel@control "test -d /home/rhel/ansible-files && test -f /home/rhel/ansible-files/inventory" 2>/dev/null; then
        echo "[setup-vscode] Control VM ansible-files directory is ready"
        break
    fi
    echo "[setup-vscode] Attempt $attempt/60: Control VM not ready, waiting 5s..."
    sleep 5
done

echo "[setup-vscode] Copying SSH public key to control VM"
# Copy our public key to control VM's authorized_keys for passwordless login
# Uses sshpass because we don't have key-based auth set up yet
# Password "ansible123!" comes from cloud-init config in instances.yaml
sshpass -p "ansible123!" ssh-copy-id -o StrictHostKeyChecking=no rhel@control 2>/dev/null || \
    echo "[setup-vscode] WARN: Could not copy SSH key to control - SSHFS mount may require password"

echo "[setup-vscode] Mounting ansible-files from control VM via SSHFS"
# Mount control VM's ansible-files directory here using SSHFS
# SSHFS options:
#   allow_other = allow users other than rhel to access the mount
#   default_permissions = check permissions on files
# If mount fails, exit immediately (setup cannot continue without shared files)
su - rhel -c 'sshfs rhel@control:/home/rhel/ansible-files /home/rhel/ansible-files -o allow_other,default_permissions' || {
    echo "[setup-vscode] ERROR: Failed to mount ansible-files from control VM"
    echo "[setup-vscode] Possible causes:"
    echo "[setup-vscode]   - Control VM setup-control.sh failed"
    echo "[setup-vscode]   - Network connectivity issue between VMs"
    echo "[setup-vscode]   - SSH key copy failed and password auth is disabled"
    echo "[setup-vscode] Check /tmp/control-setup-script.out for control VM setup logs"
    exit 1
}

echo "[setup-vscode] Adding SSHFS mount to /etc/fstab for persistence"
# Add fstab entry so mount survives VM reboots
# fstab options:
#   _netdev = mount after network is available
#   user = allow non-root users to mount/unmount
#   idmap=user = map remote user IDs to local user IDs
#   allow_other = allow access by users other than the mounting user
echo "rhel@control:/home/rhel/ansible-files /home/rhel/ansible-files fuse.sshfs defaults,_netdev,user,idmap=user,allow_other 0 0" >> /etc/fstab

echo "[setup-vscode] SSHFS mount successful - ansible-files directory is shared with control VM"
echo "[setup-vscode] Students can now edit files in VS Code and run them immediately on control VM"

# ─── code-server ─────────────────────────────────────────────────────────────

echo "[setup-vscode] Configuring code-server (browser-based VS Code)"
# code-server is pre-installed in devtools-ansible image
# We just need to configure it for lab use

# Stop code-server if it's running (will restart it later after config)
echo "[setup-vscode] Stopping code-server service"
systemctl stop code-server || true

# Backup existing config if present (preserve any manual changes)
echo "[setup-vscode] Backing up existing code-server config (if any)"
[ -f /home/rhel/.config/code-server/config.yaml ] && \
  mv /home/rhel/.config/code-server/config.yaml \
     /home/rhel/.config/code-server/config.bk.yaml || true

# Create code-server configuration
echo "[setup-vscode] Writing code-server configuration"
mkdir -p /home/rhel/.config/code-server
cat > /home/rhel/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF
# Configuration explained:
#   bind-addr: 0.0.0.0:8080 = listen on all interfaces, port 8080
#     (RHDP route maps external HTTPS to this internal HTTP port)
#   auth: none = no password required (lab is time-limited and isolated)
#   cert: false = no TLS (route handles HTTPS termination)

chown -R rhel:rhel /home/rhel/.config/code-server

# ─── LiteLLM proxy ───────────────────────────────────────────────────────────

echo "[setup-vscode] Installing LiteLLM proxy"
# LiteLLM acts as a local proxy for Ansible Lightspeed
# Why LiteLLM:
#   - Provides OpenAI-compatible API endpoint for VS Code extension
#   - Injects lab-specific context into every Lightspeed request
#   - Handles authentication with upstream MAAS (Model-as-a-Service)
#   - Allows offline development/testing by swapping backend

# Install litellm Python package with proxy extras
# Retry up to 3 times to handle transient network issues
for attempt in {1..3}; do
    echo "[setup-vscode] Installing litellm via pip (attempt $attempt/3)"
    if pip3 install --quiet 'litellm[proxy]'; then
        echo "[setup-vscode] LiteLLM installed successfully"
        break
    fi
    echo "[setup-vscode] Attempt $attempt failed, retrying in 5s..."
    sleep 5
done

echo "[setup-vscode] Creating LiteLLM configuration directory"
mkdir -p /etc/litellm

echo "[setup-vscode] Writing LiteLLM configuration"
# LiteLLM config with lab-specific system prompt
# The system prompt injects lab context so Lightspeed suggestions are contextually relevant
cat > /etc/litellm/config.yaml << 'EOF'
model_list:
  - model_name: ansible-lightspeed
    litellm_params:
      model: openai/codellama-7b-instruct
      api_base: https://litellm-prod.apps.maas.redhatworkshops.io/v1
      api_key: os.environ/MAAS_API_KEY

litellm_settings:
  system_prompt: |
    You are Ansible Lightspeed, an expert Ansible automation assistant.
    Lab environment context:
    - Student working directory: /home/rhel/ansible-files
    - Managed nodes: node1, node2, node3 (RHEL 9, SSH user: rhel)
    - Inventory groups: web=[node1, node2], database=[node3]
    - All modules must use fully qualified collection names (ansible.builtin.*, ansible.posix.*)
    - Playbooks are executed with ansible-navigator, not ansible-playbook
    - Execution environment: quay.io/acme_corp/first_playbook_ee:latest
    Respond with clean, idiomatic Ansible YAML only unless the student explicitly asks for an explanation.
EOF
# Configuration explained:
#   model_name: ansible-lightspeed = alias used by VS Code extension
#   model: openai/codellama-7b-instruct = actual LLM model to use
#   api_base: MAAS endpoint URL (Red Hat's Model-as-a-Service)
#   api_key: os.environ/MAAS_API_KEY = read from environment variable below
#   system_prompt: injected into every request for lab-specific context

echo "[setup-vscode] Creating systemd service for LiteLLM"
# Create systemd unit file for LiteLLM proxy service
cat > /etc/systemd/system/litellm.service << 'EOF'
[Unit]
Description=LiteLLM Proxy for Ansible Lightspeed
After=network.target

[Service]
Type=simple
Environment=MAAS_API_KEY=YOUR-API-KEY-HERE
ExecStart=/usr/local/bin/litellm --config /etc/litellm/config.yaml --port 4000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
# Service configuration explained:
#   Environment=MAAS_API_KEY=YOUR-API-KEY-HERE
#     ^^ TODO: Replace with real API key before production
#     ^^ Should come from AgnosticV secrets, not hardcoded
#   ExecStart: runs litellm proxy on port 4000
#   Restart=on-failure: auto-restart if it crashes
#   RestartSec=5: wait 5s before restarting

echo "[setup-vscode] Enabling and starting LiteLLM service"
systemctl daemon-reload
systemctl enable litellm  # Start on boot
systemctl start litellm   # Start now

echo "[setup-vscode] Waiting for LiteLLM service to be ready"
# Wait for service to be active and health endpoint to respond
wait_for_service litellm 60
wait_for_http "http://localhost:4000/health" 30

echo "[setup-vscode] LiteLLM proxy is running on localhost:4000"

# ─── VS Code extension settings ──────────────────────────────────────────────

echo "[setup-vscode] Configuring VS Code (code-server) extension settings"
# Configure the redhat.ansible extension to use our local LiteLLM proxy
# Settings are stored in code-server's User directory (per-user config)
mkdir -p /home/rhel/.local/share/code-server/User

# Write VS Code settings.json
cat > /home/rhel/.local/share/code-server/User/settings.json << 'EOF'
{
  "ansible.lightspeed.enabled": true,
  "ansible.lightspeed.URL": "http://localhost:4000",
  "ansible.lightspeed.suggestions.enabled": true,
  "ansible.validation.enabled": true,
  "ansible.ansible.path": "ansible",
  "editor.fontSize": 14,
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000
}
EOF
# Settings explained:
#   ansible.lightspeed.enabled: true = enable AI-powered suggestions
#   ansible.lightspeed.URL: http://localhost:4000 = use our LiteLLM proxy
#   ansible.lightspeed.suggestions.enabled: true = show inline suggestions
#   ansible.validation.enabled: true = validate Ansible syntax
#   ansible.ansible.path: "ansible" = path to ansible binary
#   editor.fontSize: 14 = readable font size for browser-based editor
#   editor.tabSize: 2 = Ansible standard is 2-space indentation
#   editor.insertSpaces: true = use spaces not tabs (Ansible YAML requirement)
#   files.autoSave: "afterDelay" = auto-save edited files
#   files.autoSaveDelay: 1000 = auto-save after 1 second of inactivity

chown -R rhel:rhel /home/rhel/.local

echo "[setup-vscode] Starting code-server service"
# Start code-server now and enable it to start on boot
systemctl start code-server
systemctl enable code-server

echo "[setup-vscode] Waiting for code-server to be ready"
# Verify code-server service is active and HTTP endpoint responds
wait_for_service code-server 60
wait_for_http "http://localhost:8080" 30

echo "[setup-vscode] ============================================"
echo "[setup-vscode] VSCode VM setup complete"
echo "[setup-vscode] ============================================"
echo "[setup-vscode] Services running:"
echo "[setup-vscode]   - code-server: http://localhost:8080"
echo "[setup-vscode]   - LiteLLM proxy: http://localhost:4000"
echo "[setup-vscode] SSHFS mount:"
echo "[setup-vscode]   - /home/rhel/ansible-files -> rhel@control:/home/rhel/ansible-files"
echo "[setup-vscode] Students can now:"
echo "[setup-vscode]   1. Open VS Code tab (proxied to this VM's port 8080)"
echo "[setup-vscode]   2. Edit files in /home/rhel/ansible-files/"
echo "[setup-vscode]   3. Use Ansible Lightspeed for AI-powered playbook generation"
echo "[setup-vscode]   4. Run playbooks in Control terminal (changes sync instantly)"
echo "[setup-vscode] ============================================"
