#!/bin/bash

# Setup script for control node
# Creates directories, ansible config, navigator config, and the lab inventory.
# The inventory is pre-created so students can focus on playbooks, not inventory writing.

set -e

# ─── Helper Functions ────────────────────────────────────────────────────────
wait_for_podman_pull() {
    local image=$1
    local max_wait=${2:-300}
    local elapsed=0

    echo "Pulling execution environment image: $image"
    # Pre-pull the image with retry logic
    for attempt in {1..3}; do
        echo "Pull attempt $attempt/3..."
        if timeout $max_wait podman pull "$image" 2>&1 | tee /tmp/podman-pull.log; then
            echo "Successfully pulled $image"
            return 0
        fi
        echo "Pull attempt $attempt failed, retrying in 10s..."
        sleep 10
    done

    echo "ERROR: Failed to pull $image after 3 attempts"
    cat /tmp/podman-pull.log
    return 1
}

# ─── Directory Setup ─────────────────────────────────────────────────────────
mkdir -p /home/rhel/ansible-files /home/rhel/.logs
chown -R rhel:rhel /home/rhel/ansible-files /home/rhel/.logs

# ─── Ansible Configuration ──────────────────────────────────────────────────
cat > /home/rhel/.ansible.cfg << 'EOF'
[defaults]
inventory = /home/rhel/ansible-files/inventory
host_key_checking = False
EOF
chown rhel:rhel /home/rhel/.ansible.cfg

cat > /home/rhel/.gitconfig << 'EOF'
[user]
  email = rhel@example.com
  name = Red Hat
EOF
chown rhel:rhel /home/rhel/.gitconfig

# ─── Ansible Navigator Configuration ────────────────────────────────────────
# ansible-navigator.yml is written to both the home dir and the working dir
# so it is picked up regardless of where the student runs commands from.
for dest in /home/rhel/.ansible-navigator.yml \
            /home/rhel/ansible-files/ansible-navigator.yml; do
  cat > "$dest" << 'EOF'
---
ansible-navigator:
  ansible:
    inventory:
      entries:
      - /home/rhel/ansible-files/inventory
  execution-environment:
    container-engine: podman
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
done
chown rhel:rhel /home/rhel/.ansible-navigator.yml \
                /home/rhel/ansible-files/ansible-navigator.yml

# ─── Pre-create Lab Inventory ───────────────────────────────────────────────
# Pre-create the inventory with all groups so the lab is ready from module 01.
# web and database groups are used in conditionals starting in module 02.
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
chown rhel:rhel /home/rhel/ansible-files/inventory

# ─── Pre-pull Execution Environment ─────────────────────────────────────────
# Pull the EE image as rhel user (ansible-navigator runs as rhel, not root)
# This prevents first-run delay when student runs their first playbook.
echo "Pre-pulling execution environment image as rhel user..."
su - rhel -c 'podman pull quay.io/acme_corp/first_playbook_ee:latest' || \
  echo "WARN: Failed to pre-pull EE image, will pull on first playbook run"

# Verify the pull succeeded
if su - rhel -c 'podman images | grep -q first_playbook_ee'; then
    echo "Execution environment image ready"
else
    echo "WARN: Execution environment image not found in podman images"
fi

echo "Control node setup complete"
