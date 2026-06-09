#!/bin/bash
#
# Setup script for control node
# Purpose: Download pre-configured Ansible files from GitHub and set up execution environment
# This VM is where students run ansible-navigator commands from the Control terminal
# Files downloaded here will be shared with vscode VM via SSHFS mount
#
set -e  # Exit immediately if any command fails

# ─── Helper Functions ────────────────────────────────────────────────────────

# Function: wait_for_podman_pull
# Purpose: Pull podman image with retry logic to handle network issues
# Args: $1=image name, $2=max wait time in seconds (default 300)
wait_for_podman_pull() {
    local image=$1
    local max_wait=${2:-300}
    local elapsed=0

    echo "[setup-control] Pulling execution environment image: $image"

    # Retry up to 3 times with 10s delay between attempts
    for attempt in {1..3}; do
        echo "[setup-control] Pull attempt $attempt/3..."

        # Use timeout to prevent hanging, tee to capture logs
        if timeout $max_wait podman pull "$image" 2>&1 | tee /tmp/podman-pull.log; then
            echo "[setup-control] Successfully pulled $image"
            return 0
        fi

        echo "[setup-control] Pull attempt $attempt failed, retrying in 10s..."
        sleep 10
    done

    # If we get here, all attempts failed
    echo "[setup-control] ERROR: Failed to pull $image after 3 attempts"
    cat /tmp/podman-pull.log
    return 1
}

# ─── Directory Setup ─────────────────────────────────────────────────────────

echo "[setup-control] Creating log directory"
# Create logs directory for ansible-navigator output
mkdir -p /home/rhel/.logs
chown -R rhel:rhel /home/rhel/.logs

# ─── Download Lab Files from GitHub ─────────────────────────────────────────

echo "[setup-control] Downloading lab files from GitHub..."
# Download specific files from main repo using GitHub raw content API
# Why curl instead of git clone:
#   1. No git dependency required on RHEL base image
#   2. Faster - only downloads needed files, not entire repo history
#   3. More reliable in restricted network environments
#   4. Works with HTTP proxies without git protocol setup

# GitHub repository base URL for raw file access
REPO_URL="https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main"

echo "[setup-control] Cleaning up any existing ansible-files directory"
# Remove existing directory to ensure clean state
rm -rf /home/rhel/ansible-files

echo "[setup-control] Creating directory structure"
# Create ansible-files and templates subdirectory
mkdir -p /home/rhel/ansible-files/templates

# Function: download_file
# Purpose: Download a file from GitHub with retry logic
# Args: $1=URL, $2=destination path
# Returns: 0 on success, 1 on failure after 3 attempts
download_file() {
    local url=$1
    local dest=$2
    local max_attempts=3

    # Retry download up to 3 times with 2s delay
    for attempt in $(seq 1 $max_attempts); do
        # curl flags: -f=fail on HTTP error, -s=silent, -S=show errors, -L=follow redirects
        if curl -fsSL "$url" -o "$dest"; then
            echo "[setup-control] Downloaded: $(basename $dest)"
            return 0
        fi
        echo "[setup-control] Attempt $attempt failed for $(basename $dest), retrying..."
        sleep 2
    done

    echo "[setup-control] ERROR: Failed to download $(basename $dest) after $max_attempts attempts"
    return 1
}

echo "[setup-control] Downloading configuration files"
# Download each required file - exit immediately if any download fails
# These files are the foundation of the student workspace
download_file "$REPO_URL/ansible-files/ansible.cfg" "/home/rhel/ansible-files/ansible.cfg" || exit 1
download_file "$REPO_URL/ansible-files/ansible-navigator.yml" "/home/rhel/ansible-files/ansible-navigator.yml" || exit 1
download_file "$REPO_URL/ansible-files/inventory" "/home/rhel/ansible-files/inventory" || exit 1
download_file "$REPO_URL/ansible-files/templates/motd.j2" "/home/rhel/ansible-files/templates/motd.j2" || exit 1

echo "[setup-control] Setting file ownership to rhel user"
# Set ownership so student user (rhel) can read/write these files
chown -R rhel:rhel /home/rhel/ansible-files

echo "[setup-control] Verifying all required files exist"
# Sanity check - verify each file was downloaded successfully
# This catches issues like 404 errors that curl might not report as failures
for file in ansible.cfg ansible-navigator.yml inventory templates/motd.j2; do
    if [ ! -f "/home/rhel/ansible-files/$file" ]; then
        echo "[setup-control] ERROR: Required file $file not found after download"
        echo "[setup-control] This usually means GitHub is unreachable or the file was moved/deleted in the repo"
        exit 1
    fi
done
echo "[setup-control] Lab files successfully downloaded and verified"

# ─── User Configuration ──────────────────────────────────────────────────────

echo "[setup-control] Creating user-level Ansible configuration"
# Create .ansible.cfg in home directory to point at our inventory
# This is loaded automatically by ansible/ansible-navigator commands
cat > /home/rhel/.ansible.cfg << 'EOF'
[defaults]
inventory = /home/rhel/ansible-files/inventory
host_key_checking = False
EOF
chown rhel:rhel /home/rhel/.ansible.cfg

echo "[setup-control] Creating git configuration"
# Set up git config so students can commit/push their playbooks if desired
cat > /home/rhel/.gitconfig << 'EOF'
[user]
  email = rhel@example.com
  name = Red Hat
EOF
chown rhel:rhel /home/rhel/.gitconfig

# ─── Ansible Navigator Configuration ────────────────────────────────────────

echo "[setup-control] Configuring ansible-navigator"
# Copy ansible-navigator.yml to home directory
# Why copy instead of symlink:
#   - ansible-navigator checks both /home/rhel/ and working directory
#   - Having it in home ensures it's found regardless of where student runs commands
#   - Students might delete ansible-files directory during exercises
cp /home/rhel/ansible-files/ansible-navigator.yml /home/rhel/.ansible-navigator.yml
chown rhel:rhel /home/rhel/.ansible-navigator.yml

# ─── Pre-pull Execution Environment ─────────────────────────────────────────

# Pull the EE image as rhel user (ansible-navigator runs as rhel, not root)
# Why pre-pull:
#   - First ansible-navigator run would trigger 2-5 min download
#   - Students think the lab is broken when they see pulling image
#   - Pre-pulling during setup makes first playbook run instant
echo "[setup-control] Pre-pulling execution environment image as rhel user..."
su - rhel -c 'podman pull quay.io/acme_corp/first_playbook_ee:latest' || \
  echo "[setup-control] WARN: Failed to pre-pull EE image, will pull on first playbook run"

# Verify the pull succeeded by checking podman images list
echo "[setup-control] Verifying execution environment image"
if su - rhel -c 'podman images | grep -q first_playbook_ee'; then
    echo "[setup-control] Execution environment image ready"
else
    echo "[setup-control] WARN: Execution environment image not found in podman images"
    echo "[setup-control] Student will experience delay on first ansible-navigator run"
fi

echo "[setup-control] Control node setup complete"
echo "[setup-control] Files are now ready for SSHFS mount from vscode VM"
