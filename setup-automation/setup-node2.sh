#!/bin/bash

# Setup script for node2
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
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "WARN: Package manager may not be fully initialized"
    return 0  # Non-fatal, continue anyway
}

# ─── Wait for System Readiness ──────────────────────────────────────────────
# Note: All three nodes run this setup in parallel via the showroom runner
wait_for_dnf 60

echo "Node2 setup complete - SSH access enabled via cloud-init"
