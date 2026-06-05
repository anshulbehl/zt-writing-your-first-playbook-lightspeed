# AWS to CNV Conversion Summary

## Conversion Approach

This lab now uses the **composite catalog item pattern** - it references the base `zt-ans-bu-lab-developer-cnv` component instead of duplicating all CNV configuration.

### Catalog Item Structure

**Composite Pattern** (~/Projects/agnosticv_all/zt-ansiblebu-agnosticv/zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/):
- `common.yaml`: ~40 lines (vs 227 in standalone)
- Just overrides: git repo URL, timeout
- Uses `__meta__.deployer.type: null` (composite marker)
- References component: `zt-ansiblebu/zt-ans-bu-lab-developer-cnv`

### Showroom Repository Changes

**Created:**
1. `config/instances.yaml` - 5 VMs (control, node1-3, vscode)
2. `config/firewall.yaml` - Basic egress rules (HTTPS, HTTP, DNS)
3. `config/networks.yaml` - Default pod network
4. `ui-config.yml` - Modern tab format with URL substitution
5. `setup-automation/main.yml` - VM provisioning playbook
6. `setup-automation/setup-control.sh` - Control node directories
7. `setup-automation/setup-vscode.sh` - VSCode workspace config
8. `setup-automation/setup-node{1,2,3}.sh` - Minimal worker setup

**Preserved:**
- `zero-touch-config.yml` - Original AWS UI config (for AWS catalog item)
- `runtime-automation/` - Solve button automation (works for both AWS and CNV)

## VM Configuration

| VM | Image | RAM | Cores | Disk | Purpose |
|----|-------|-----|-------|------|---------|
| control | rhel-9.6 | 4G | 2 | 30Gi | Control node for Ansible |
| node1-3 | rhel-9.6 | 2G | 2 | 30Gi | Managed nodes |
| vscode | devtools-ansible | 4G | 2 | 20Gi | VSCode web editor |

**Key Details:**
- All VMs use cloud-init for user setup (rhel/ansible123!)
- VSCode VM uses prebuilt `devtools-ansible` image (code-server on port 8080)
- VSCode VM requires `disk_type: scsi` and `bootloader: efi`

## UI Tabs (Modern Format)

```yaml
tabs:
  - name: VS Code
    url: https://vscode-${guid}.${domain}/
    external: false
  - name: Control
    url: /wetty
    external: false
```

**Changes from AWS:**
- Old: `port: 8443, path: /?folder=/home/rhel/ansible-files/`
- New: `url: https://vscode-${guid}.${domain}/` (route-based)
- Control terminal: `/wetty` (wetty SSH bastion provided by base component)

## Setup Automation

**Execution flow:**
1. Showroom pod init containers: git-cloner → antora-builder → **setup**
2. Setup runs `ansible-playbook /showroom/repo/setup-automation/main.yml`
3. Playbook creates dynamic inventory from BASTION_* env vars
4. Copies and executes setup-*.sh scripts on each VM
5. Main containers start after setup completes

**Timeout:** 1200 seconds (20 minutes) - allows for VM provisioning + setup

## Cloud Selector

Uses `/includes/cloud-selector-cnv.yaml`:
```yaml
cloud_selector:
  cloud: cnv
  purpose: prod
  virt: "yes"
```

**Targets:** Legacy CNV clusters (`ocpv05`, `ocpv08`, `ocpv10`)

## Image Requirements

| Image | Status | Notes |
|-------|--------|-------|
| rhel-9.6 | ✅ Standard | Should exist in `cnv-images` namespace |
| devtools-ansible | ⚠️ Verify | Prebuilt VSCode image - confirm availability |

If `devtools-ansible` doesn't exist, alternatives:
1. Request via PTMP team (manual upload)
2. Install code-server in setup-control.sh (slower, more complex)

## Testing Checklist

- [ ] Verify `rhel-9.6` PVC exists on target cluster
- [ ] Verify `devtools-ansible` PVC exists (or request it)
- [ ] Test in dev environment first
- [ ] Check all 5 VMs provision successfully
- [ ] Verify setup automation completes without timeout
- [ ] Access VS Code tab - confirm editor loads
- [ ] Access Control tab - confirm wetty terminal works
- [ ] Test SSH: `ssh node1` from control VM
- [ ] Test solve button on module 01

## Files Modified

**Showroom repo:**
- NEW: `config/` directory (instances.yaml, firewall.yaml, networks.yaml)
- NEW: `ui-config.yml` (root level, modern format)
- NEW: `setup-automation/` directory (main.yml + 5 setup scripts)
- PRESERVED: `zero-touch-config.yml` (AWS compatibility)
- PRESERVED: `runtime-automation/` (unchanged)

**Catalog repo:**
- NEW: `zt-ans-bu-writing-playbook-cnv/` (composite item)
  - common.yaml (40 lines vs 227 standalone)
  - dev/test/prod/event.yaml (environment overlays)
  - description.adoc

## Next Steps

1. **Push showroom changes:**
   ```bash
   cd ~/Projects/showrooms_all/zt-writing-your-first-playbook/
   git add config/ ui-config.yml setup-automation/ CONVERSION_SUMMARY.md
   git commit -m "Add CNV support with composite pattern"
   git push origin main
   ```

2. **Validate catalog item:**
   ```bash
   cd ~/Projects/agnosticv_all/zt-ansiblebu-agnosticv/
   agnosticv --merge
   python3 babylon_checks.py
   ```

3. **Deploy to dev and verify all VMs provision correctly**

## Key Differences from Initial Attempt

| Aspect | Initial (Wrong) | Corrected |
|--------|----------------|-----------|
| **Catalog pattern** | Standalone (227 lines) | Composite (40 lines) |
| **ui-config.yml location** | config/ directory | Root directory |
| **VSCode approach** | Custom nginx on control VM | Separate VM with devtools-ansible image |
| **Tab format** | port/path (deprecated) | url with ${guid}/${domain} |
| **VM count** | 4 (control + 3 nodes) | 5 (+ vscode VM) |

---

**Date:** 2026-06-05  
**Pattern:** Ansible BU composite (references zt-ans-bu-lab-developer-cnv)  
**Status:** Ready for testing (verify devtools-ansible image availability first)
