# Provisioning Fix - Inventory File Not Created

## Problem

The inventory file was not being created in `/home/rhel/ansible-files/inventory` during lab provisioning, even though `setup-control.sh` contains the code to create it.

## Root Cause

In `setup-automation/main.yml`, the `add_host` loop was missing `control`:

```yaml
# BEFORE (BROKEN)
loop:
  - node1
  - node2
  - node3
  - vscode
```

The second play in `main.yml` targets `hosts: all:!localhost`, which means it runs setup scripts on all hosts that were added via `add_host`. Since `control` was never added to the inventory, `setup-control.sh` was never executed.

## Fix Applied

Added `control` to the `add_host` loop:

```yaml
# AFTER (FIXED)
loop:
  - control      # ← ADDED
  - node1
  - node2
  - node3
  - vscode
```

**File modified:** `setup-automation/main.yml` (line 25)

## Verification

All VMs in `config/instances.yaml` now match the setup loop:

| VM | In instances.yaml | In setup loop | Script exists |
|----|-------------------|---------------|---------------|
| control | ✅ | ✅ | setup-control.sh ✅ |
| node1 | ✅ | ✅ | setup-node1.sh ✅ |
| node2 | ✅ | ✅ | setup-node2.sh ✅ |
| node3 | ✅ | ✅ | setup-node3.sh ✅ |
| vscode | ✅ | ✅ | setup-vscode.sh ✅ |

## What Gets Created Now

When the lab provisions, `setup-control.sh` will now execute and create:

1. `/home/rhel/ansible-files/` directory
2. `/home/rhel/ansible-files/inventory` with all groups:
   ```ini
   [web]
   node1
   node2

   [database]
   node3

   [nodes:children]
   web
   database
   ```
3. `/home/rhel/.ansible.cfg`
4. `/home/rhel/.gitconfig`
5. `/home/rhel/.ansible-navigator.yml`
6. `/home/rhel/ansible-files/ansible-navigator.yml`
7. Pre-pull the execution environment image

## Testing

To verify the fix works:

1. Deploy the lab
2. SSH to the control node
3. Check that the inventory exists:
   ```bash
   ls -la /home/rhel/ansible-files/inventory
   cat /home/rhel/ansible-files/inventory
   ```
4. Verify all groups are present: `[web]`, `[database]`, `[nodes:children]`

Expected output:
```
-rw-r--r-- 1 rhel rhel 67 Jun  9 14:30 /home/rhel/ansible-files/inventory
```

## Related Issues

This was the final blocker preventing students from starting Module 01, where they explore the pre-created inventory file in VS Code.

Without this fix:
- ❌ Students would see an empty `ansible-files` directory
- ❌ Module 01 Task 2 would fail (no inventory file to open)
- ❌ Module 03 would fail (ansible-navigator can't find inventory)

With this fix:
- ✅ Inventory is pre-created during provisioning
- ✅ Students can immediately open and explore it in Module 01
- ✅ All modules can run playbooks against the inventory
