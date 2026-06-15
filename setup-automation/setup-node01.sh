#!/bin/bash

# Setup script for node1
# Minimal setup - SSH access already configured via cloud-init
# Wait for package manager to be ready (cloud-init may still be running)

set -e

# ─── Helper Functions ────────────────────────────────────────────────────────
wait_for_dnf() {
    local max_wait=${1:-60}
    local elapsed=0

    echo "Waiting for dnf/yum to be available (cloud-init may be running)..."
    while [ $elapsed -lt $max_wait ]; do
        if dnf check-update --quiet 2>/dev/null || [ $? -eq 100 ]; then
            echo "Package manager is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    echo "WARN: Package manager may not be fully initialized"
    return 0  # Non-fatal, continue anyway
}

# ─── Wait for System Readiness ──────────────────────────────────────────────
wait_for_dnf 60

# ─── Open SSH Port ──────────────────────────────────────────────────────────
echo "Configuring firewall to allow SSH..."

# Ensure firewalld is installed and running
if ! systemctl is-active --quiet firewalld; then
    echo "Starting firewalld service..."
    if systemctl start firewalld 2>/dev/null; then
        echo "Firewalld started successfully"
    else
        echo "WARNING: firewalld not available, attempting iptables fallback"
        # Fallback to iptables if firewalld isn't available
        if command -v iptables &>/dev/null; then
            iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || echo "WARNING: iptables command failed"
        fi
    fi
fi

# Open SSH port if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "Opening SSH port 22 in firewalld..."
    if firewall-cmd --permanent --add-service=ssh 2>/dev/null && firewall-cmd --reload 2>/dev/null; then
        echo "SSH port opened successfully via firewalld"
    else
        echo "WARNING: firewall-cmd failed, SSH may be blocked"
    fi
else
    echo "WARNING: firewalld not active, SSH access depends on default firewall state"
fi

echo "Node01 setup complete"
