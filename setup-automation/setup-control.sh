#!/bin/bash

# Setup script for control node
# Creates directories, ansible config, navigator config, and the lab inventory.
# The inventory is pre-created so students can focus on playbooks, not inventory writing.

set -e

mkdir -p /home/rhel/ansible-files /home/rhel/.logs
chown -R rhel:rhel /home/rhel/ansible-files /home/rhel/.logs

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

# Pre-create the inventory with all groups so the lab is ready from module 01.
# web and database groups are used in conditionals (module 06+).
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

echo "Control node setup complete"
