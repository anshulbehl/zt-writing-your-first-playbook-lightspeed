# AWS to CNV Conversion - Writing Your First Playbook Lab

## Overview

This document details the conversion of the "Writing Your First Playbook" lab from AWS EC2 to OpenShift CNV.

## What Was Converted

### Source (AWS-based)
- **Catalog Item**: `zt-ansiblebu/zt-ans-bu-writing-playbook/common.yaml`
- **Infrastructure**: 4 EC2 instances (1 control, 3 nodes)
- **Deployment**: vscode-server + showroom roles on bastion host
- **Networking**: AWS VPC with security groups

### Target (CNV-based)
- **Catalog Item**: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/common.yaml`
- **Infrastructure**: 4 CNV VMs (control, node1, node2, node3)
- **Deployment**: Showroom Helm chart with zerotouch pattern
- **Networking**: OpenShift pod network with default configuration

## Files Created

### 1. Showroom Repository (`~/Projects/showrooms_all/zt-writing-your-first-playbook/`)

#### `config/` Directory (NEW)
- **`instances.yaml`** - Defines 4 VMs with RHEL 9.5:
  - `control`: 8G RAM, 2 cores, 50Gi disk, routes for HTTPS (443) and VSCode (8443)
  - `node1`, `node2`, `node3`: 4G RAM each, 2 cores, 30Gi disk
  - All VMs use cloud-init for user setup and SSH password authentication
  
- **`ui-config.yml`** - Renamed from `zero-touch-config.yml`:
  - 10 interactive modules with solve buttons
  - 2 tabs: VSCode Editor (8443) and Control terminal (443)
  
- **`firewall.yaml`** - Network egress rules:
  - Allow HTTPS (443), HTTP (80), DNS (53)
  
- **`networks.yaml`** - Minimal network config (uses default pod network)

#### `setup-automation/` Directory (NEW)
- **`main.yml`** - Ansible playbook that:
  - Creates dynamic inventory from BASTION_* env vars
  - Copies and executes setup scripts on each VM
  - Waits for SSH connectivity
  - Handles setup failures with proper error reporting

- **`setup-control.sh`** - Control node setup:
  - Installs: git, podman, python3-devel, systemd-container, unzip, pip
  - Installs podman-compose 1.0.6
  - Creates `/home/rhel/ansible-files/` directory
  - Creates ansible.cfg with proper inventory path
  - Enables podman socket for showroom integration

- **`setup-node1.sh`, `setup-node2.sh`, `setup-node3.sh`** - Worker node setup:
  - Minimal scripts (SSH already configured via cloud-init)
  - Can be extended with additional setup as needed

- **`ansible.cfg`** - Basic Ansible configuration for setup playbook

### 2. Catalog Item (`~/Projects/agnosticv_all/zt-ansiblebu-agnosticv/zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/`)

#### `common.yaml` - Main catalog configuration
Key changes from AWS version:
- `env_type: zero-touch-base-rhel` (was `zero-touch-ansible-bu`)
- `cloud_provider: openshift_cnv` (was `ec2`)
- Dynamic config loading via `git_config_directory` Jinja2 template
- Loads instances, firewall, networks from showroom repo
- Uses Showroom Helm chart (zerotouch v1.10.2)
- Extended timeout: `ocp4_workload_showroom_namespace_wait_ready: 1200` (20 minutes)
- Enabled setup automation: `ocp4_workload_showroom_setup_automation_setup: "true"`
- Uses `ansiblebu_rhel_password` secret for user credentials

#### Environment Overlays
- **`dev.yaml`** - Development environment with CNV cloud selector
- **`test.yaml`** - Test environment
- **`prod.yaml`** - Production environment
- **`event.yaml`** - Event/summit environment

All overlays include:
```yaml
#include /includes/cloud-selector-cnv.yaml
#include /includes/lifetime-standard.yaml  # or lifetime-event.yaml
```

#### `description.adoc` - Catalog display text
- Overview of lab content
- Environment details (1 control + 3 nodes)
- Learning objectives (10 modules)
- Prerequisites
- Access information

## Key Differences: AWS vs CNV

| Aspect | AWS (EC2) | CNV (OpenShift) |
|--------|-----------|-----------------|
| **Infrastructure** | EC2 instances in VPC | CNV VMs in OCP namespace |
| **Image** | AMI (zt-control-19-july-2024, zt-node-19-july-2024) | PVC clone (rhel-9.5) |
| **Networking** | Security groups, floating IPs | Pod network, OCP routes |
| **User setup** | AgnosticD playbooks | cloud-init userdata |
| **VSCode** | nginx reverse proxy (vscode-server role) | OCP route to VM port 8443 |
| **Terminal** | showroom container SSH to host.containers.internal | wetty SSH to bastion VM |
| **Setup automation** | Ansible roles (vscode-server, showroom) | setup-automation playbook + shell scripts |
| **DNS** | Route53 / sandbox DNS | OCP routes with wildcard DNS |
| **Provisioning time** | ~10-15 minutes | ~15-20 minutes (includes VM image cloning) |

## Cloud Selector Targeting

The catalog item uses the following cloud selector to target CNV clusters:

```yaml
#include /includes/cloud-selector-cnv.yaml
```

This resolves to:
```yaml
cloud_selector:
  cloud: cnv
  purpose: prod
  virt: "yes"
```

**Matches clusters**: `ocpv05`, `ocpv08`, `ocpv10` (legacy bare-metal CNV prod clusters)

**Does NOT match**: HCP clusters (`cnv-us-east-ocp-*`, `cnv-us-south-ocp-*`) - those require `cloud: cnv-shared`

## VM Image Requirements

The catalog item expects a PVC named `rhel-9.5` in the `cnv-images` namespace on the target CNV cluster.

**Current status**: Standard RHEL 9.5 cloud image should already exist in platform image catalog.

If the image doesn't exist, request via PTMP team (manual upload process):
1. Provide QCOW2 source URL
2. Team uploads to dev cluster via `virtctl image-upload`
3. Team creates DataVolume CR in `rhpds/infra` repo
4. ArgoCD syncs to production clusters

## Runtime Automation

The original AWS catalog item uses `runtime-automation/` folder in the showroom repo for solve button automation. **This is preserved and unchanged** - the runtime automation works identically in CNV:

- 10 modules with setup/solve/validation playbooks
- Ansible Runner API executes playbooks in showroom container
- Inventory file references: `control`, `node1`, `node2`, `node3`
- SSH via `/app/.ssh/labkey.pem` (Babylon provisioning key)

## Setup Automation Deep Dive

### Lifecycle

1. **Showroom pod starts** with init containers:
   - `git-cloner`: Clones showroom repo (includes `setup-automation/`)
   - `antora-builder`: Builds documentation site
   - `setup` (conditional): Runs only if `ocp4_workload_showroom_setup_automation_setup: "true"`

2. **Setup init container** executes:
   ```bash
   ansible-playbook /showroom/repo/setup-automation/main.yml
   ```

3. **Main playbook** (`setup-automation/main.yml`):
   - Creates dynamic inventory from environment variables:
     - `BASTION_HOST`, `BASTION_PORT`, `BASTION_USER`, `BASTION_PASSWORD`
   - Adds control node and 3 worker nodes to inventory
   - Waits for SSH connectivity (port 22)
   - Copies setup scripts to `/tmp/setup-scripts/` on each VM
   - Executes setup script as root via `become: true`
   - Captures output and fails on non-zero exit code

4. **Setup scripts** run sequentially:
   - `setup-control.sh`: Installs packages, creates directories, configures Ansible
   - `setup-node*.sh`: Currently minimal (can be extended)

5. **Main containers start** only after setup init completes successfully

### Timeout Configuration

**Critical**: Setup automation adds significant time to deployment.

- **Catalog setting**: `ocp4_workload_showroom_namespace_wait_ready: 1200` (20 minutes)
- **Default**: 900 seconds (15 minutes)
- **Recommendation**: For labs with heavy setup, use 2700+ seconds (45 minutes)

If setup exceeds the timeout:
- Pod enters `CrashLoopBackOff`
- Setup init container shows `Error` status
- Check logs: `oc logs <pod> -c setup -n <namespace>`

## Testing Checklist

Before deploying to production:

- [ ] Verify `rhel-9.5` PVC exists in `cnv-images` namespace on target cluster
- [ ] Test catalog item in dev environment first
- [ ] Check VM provisioning completes (all 4 VMs Running)
- [ ] Verify setup automation completes without errors
- [ ] Access VSCode tab - confirm file editor loads at `/home/rhel/ansible-files/`
- [ ] Access Control tab - confirm terminal connects to control VM
- [ ] Test solve buttons - run one playbook to verify runtime automation works
- [ ] Verify SSH connectivity between control and nodes: `ssh node1`
- [ ] Check ansible inventory: `ansible -i inventory all -m ping`

## Troubleshooting

### Common Issues

**Problem**: VMs not starting
- Check: `oc get vms -n <namespace>`
- Check: `oc get dvs -n <namespace>` (DataVolumes)
- Check events: `oc get events -n <namespace> --sort-by='.lastTimestamp'`
- Likely cause: `rhel-9.5` PVC missing in `cnv-images`

**Problem**: Setup automation timeout
- Check: `oc logs <pod> -c setup -n <namespace>`
- Increase: `ocp4_workload_showroom_namespace_wait_ready` parameter
- Check: VM SSH connectivity from setup container

**Problem**: VSCode tab not loading
- Check: Control VM has route for port 8443
- Check: `oc get routes -n <namespace>`
- Check: nginx or VSCode server running on control VM

**Problem**: Runtime automation (solve buttons) not working
- Check: Showroom container has access to VMs
- Check: SSH key mounted at `/app/.ssh/labkey.pem`
- Check: Ansible Runner API logs in showroom pod
- Verify: Inventory file has correct hostnames (control, node1-3)

## Next Steps

1. **Push showroom changes to GitHub**:
   ```bash
   cd ~/Projects/showrooms_all/zt-writing-your-first-playbook/
   git add config/ setup-automation/
   git commit -m "Add CNV support: config and setup-automation"
   git push origin main
   ```

2. **Test catalog item**:
   ```bash
   cd ~/Projects/agnosticv_all/zt-ansiblebu-agnosticv/
   agnosticv --merge
   python3 babylon_checks.py
   ```

3. **Deploy to dev sandbox**:
   - Use Babylon UI to provision zt-ans-bu-writing-playbook-cnv
   - Select dev environment
   - Monitor deployment logs
   - Test full lab workflow

4. **Iterate based on findings**:
   - Adjust setup scripts if needed
   - Tune timeout values
   - Update VM resource allocations if necessary

## Files Modified

### Showroom Repository
- NEW: `config/instances.yaml`
- NEW: `config/ui-config.yml`
- NEW: `config/firewall.yaml`
- NEW: `config/networks.yaml`
- NEW: `setup-automation/main.yml`
- NEW: `setup-automation/ansible.cfg`
- NEW: `setup-automation/setup-control.sh`
- NEW: `setup-automation/setup-node1.sh`
- NEW: `setup-automation/setup-node2.sh`
- NEW: `setup-automation/setup-node3.sh`
- PRESERVED: `zero-touch-config.yml` (still used by AWS catalog item)
- PRESERVED: `runtime-automation/` (unchanged - works for both AWS and CNV)

### Catalog Repository
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/common.yaml`
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/dev.yaml`
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/test.yaml`
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/prod.yaml`
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/event.yaml`
- NEW: `zt-ansiblebu/zt-ans-bu-writing-playbook-cnv/description.adoc`
- PRESERVED: `zt-ansiblebu/zt-ans-bu-writing-playbook/` (AWS catalog item unchanged)

## Conversion Pattern Summary

This conversion follows the standard AWS → CNV pattern:

1. ✅ Create `config/instances.yaml` with VM definitions
2. ✅ Create `config/ui-config.yml` for Showroom UI
3. ✅ Create `setup-automation/` with Ansible playbook and shell scripts
4. ✅ Create CNV catalog item with `cloud_provider: openshift_cnv`
5. ✅ Use dynamic config loading pattern from git repo
6. ✅ Enable setup automation in catalog item
7. ✅ Increase timeout for VM provisioning + setup
8. ✅ Use cloud-init for basic user/SSH configuration
9. ✅ Use OCP routes for external access (VSCode, terminal)
10. ✅ Preserve runtime-automation for solve button functionality

---

**Date**: 2026-06-05  
**Converted by**: Claude Code  
**Pattern**: Standard Ansible BU lab (AWS → CNV)  
**Status**: Ready for testing
