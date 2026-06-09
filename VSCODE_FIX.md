# VS Code ansible-files Sync Fix - SSHFS Mount Solution

## Problem

When students open VS Code, the `ansible-files` directory appears empty even though it exists on the control VM with all the required files (inventory, ansible.cfg, templates/motd.j2).

**Root cause:** 
- `setup-control.sh` downloads ansible-files to the **control** VM
- code-server runs on the **vscode** VM  
- These are two separate machines, so VS Code can't see the files from control
- Students edit in VS Code (vscode VM) but run ansible-navigator in Control terminal (control VM)
- **Files must be shared** - they need a single source of truth

## Solution: SSHFS Mount

Modified `setup-automation/setup-vscode.sh` to mount the control VM's `/home/rhel/ansible-files` directory on the vscode VM using SSHFS.

### How it works:
1. **Files live on control VM** - setup-control.sh downloads from GitHub
2. **vscode VM mounts them via SSHFS** - students see the same files in VS Code
3. **Single source of truth** - edits in VS Code immediately appear on control VM
4. **ansible-navigator runs on control** - sees the same files students are editing

## Architecture

```
┌─────────────────────────────────────────┐
│  control VM                             │
│  ┌───────────────────────────────────┐  │
│  │ /home/rhel/ansible-files/         │  │
│  │  ├── ansible.cfg                  │  │
│  │  ├── ansible-navigator.yml        │  │
│  │  ├── inventory                    │  │
│  │  └── templates/motd.j2            │  │
│  └───────────────────────────────────┘  │
│         ▲                                │
│         │ SSHFS mount                    │
│         │                                │
└─────────┼────────────────────────────────┘
          │
┌─────────┼────────────────────────────────┐
│  vscode VM                               │
│  ┌───────────────────────────────────┐  │
│  │ /home/rhel/ansible-files/         │  │
│  │  (mounted from control VM)        │  │
│  └───────────────────────────────────┘  │
│         ▲                                │
│         │                                │
│  ┌──────┴─────────────────────────────┐ │
│  │  code-server (VS Code)             │ │
│  │  Students edit files here          │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

## Changes to setup-vscode.sh

1. **Install fuse-sshfs** package
2. **Generate SSH key** for passwordless access to control
3. **Wait for control VM** to complete setup and have ansible-files ready
4. **Mount via SSHFS**: `sshfs rhel@control:/home/rhel/ansible-files /home/rhel/ansible-files`
5. **Add to fstab** for persistence across reboots
6. **Verification** to ensure mount succeeded

## Benefits

✅ **Single source of truth** - files exist only on control VM  
✅ **Real-time sync** - edits in VS Code immediately visible to ansible-navigator  
✅ **No duplication** - no need to keep two copies in sync  
✅ **Transparent to students** - they just see ansible-files in both environments  
✅ **Persistent** - mount survives reboots via fstab entry

## Testing Checklist

When testing the next deployment:

1. ✅ Open VS Code tab
2. ✅ Verify `/home/rhel/ansible-files/` directory exists and is not empty
3. ✅ Verify `inventory` file is present with [web], [database], [nodes:children] groups
4. ✅ Verify `templates/` folder exists with `motd.j2` inside
5. ✅ Verify `ansible.cfg` and `ansible-navigator.yml` are present
6. ✅ Open Control terminal, verify same files exist at `/home/rhel/ansible-files/`
7. ✅ Edit `inventory` in VS Code, verify change appears immediately in Control terminal:
   ```bash
   # In VS Code: add a comment to inventory
   # In Control terminal:
   cat /home/rhel/ansible-files/inventory | grep "#"
   ```
8. ✅ Run `mount | grep ansible-files` in vscode VM to verify SSHFS mount is active

## Troubleshooting

If ansible-files appears empty in VS Code:

1. SSH to vscode VM: check `mount | grep ansible-files`
2. If mount is missing: `su - rhel -c 'sshfs rhel@control:/home/rhel/ansible-files /home/rhel/ansible-files'`
3. Verify control VM has files: `ssh rhel@control "ls -la /home/rhel/ansible-files"`
4. Check sshfs logs: `journalctl -u sshfs` or `dmesg | grep fuse`
