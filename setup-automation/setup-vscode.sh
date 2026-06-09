#!/bin/bash

# Setup script for vscode VM
# Configures code-server, installs LiteLLM proxy for Ansible Lightspeed,
# and configures the redhat.ansible VS Code extension to point at the proxy.

set -e

# ─── Helper Functions ────────────────────────────────────────────────────────
wait_for_service() {
    local service=$1
    local max_wait=${2:-60}
    local elapsed=0

    echo "Waiting for $service to be active..."
    while [ $elapsed -lt $max_wait ]; do
        if systemctl is-active --quiet "$service"; then
            echo "$service is active"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: $service failed to start within ${max_wait}s"
    systemctl status "$service" --no-pager || true
    return 1
}

wait_for_http() {
    local url=$1
    local max_wait=${2:-60}
    local elapsed=0

    echo "Waiting for $url to respond..."
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf "$url" >/dev/null 2>&1; then
            echo "$url is responding"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: $url not responding within ${max_wait}s"
    return 1
}

# ─── code-server ─────────────────────────────────────────────────────────────
mkdir -p /home/rhel/ansible-files
chown -R rhel:rhel /home/rhel/ansible-files

systemctl stop code-server || true

[ -f /home/rhel/.config/code-server/config.yaml ] && \
  mv /home/rhel/.config/code-server/config.yaml \
     /home/rhel/.config/code-server/config.bk.yaml || true

mkdir -p /home/rhel/.config/code-server
cat > /home/rhel/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF
chown -R rhel:rhel /home/rhel/.config/code-server

# ─── LiteLLM proxy ───────────────────────────────────────────────────────────
echo "Installing LiteLLM proxy..."
# Retry pip install in case of network issues
for attempt in {1..3}; do
    if pip3 install --quiet 'litellm[proxy]'; then
        echo "LiteLLM installed successfully"
        break
    fi
    echo "Attempt $attempt failed, retrying in 5s..."
    sleep 5
done

mkdir -p /etc/litellm

# Hidden system prompt injects lab context into every Lightspeed request.
# api_key is read from the MAAS_API_KEY environment variable set in the
# systemd service below — do not hardcode the key in this file.
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

systemctl daemon-reload
systemctl enable litellm
systemctl start litellm

# Wait for LiteLLM to be ready
wait_for_service litellm 60
wait_for_http "http://localhost:4000/health" 30

# ─── VS Code extension settings ──────────────────────────────────────────────
# Points the redhat.ansible extension's Lightspeed feature at the local proxy.
mkdir -p /home/rhel/.local/share/code-server/User

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
chown -R rhel:rhel /home/rhel/.local

systemctl start code-server
systemctl enable code-server

# Wait for code-server to be ready
wait_for_service code-server 60
wait_for_http "http://localhost:8080" 30

echo "VSCode VM setup complete — LiteLLM proxy listening on localhost:4000, code-server on :8080"
