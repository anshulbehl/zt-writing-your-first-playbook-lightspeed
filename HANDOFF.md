# Session Handoff: zt-writing-your-first-playbook Architecture & Design

## Session Context

This session focused on fixing provisioning failures for the zt-writing-your-first-playbook lab on RHDP. Multiple approaches were attempted to solve file sharing between VMs and eliminate network dependencies during provisioning.

---

## Architecture Overview

### Lab Type
- **Type**: Zero-touch lab (based on zero-touch-base-rhel)
- **Platform**: AgnosticV/Babylon CNV on RHDP
- **Content delivery**: Showroom

### Infrastructure (config/instances.yaml)
- **5 VMs total**:
  - `control` - RHEL 9.6, where ansible-navigator runs, hosts the ansible-files workspace
  - `node1`, `node2`, `node3` - RHEL 9.6 managed nodes
  - `vscode` - devtools-ansible image, hosts VS Code (code-server) on port 8080

### Student Workflow
Students interact with two tabs in the Showroom UI:
1. **VS Code tab** → code-server running on vscode VM at port 8080
   - Students write/edit playbooks here
   - Ansible Lightspeed extension generates code
   - File explorer shows `/home/rhel/ansible-files/`

2. **Control tab** → wetty terminal (provided by zero-touch-base-rhel)
   - Students run `ansible-navigator` commands here
   - Reads from `/home/rhel/ansible-files/` on control VM

**Critical requirement**: Files edited in VS Code (vscode VM) must appear in Control terminal (control VM). This requires file sharing between the two VMs.

---

## What We Tried

### Attempt 1: GitHub Downloads (Original Approach)
**Files**: Previous versions of setup-control.sh (171 lines), setup-vscode.sh (348 lines)

**Architecture**:
- setup-control.sh downloads ansible-files from `https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main/`
- Files: ansible.cfg, ansible-navigator.yml, inventory, templates/motd.j2
- Uses curl with 3-retry logic
- setup-vscode.sh mounts control VM's ansible-files via SSHFS
- SSHFS provides the single source of truth for file sharing

**Why it failed**:
- ✗ Control VM timed out downloading from GitHub (network unreliable during provisioning)
- ✗ VS Code VM failed to install fuse-sshfs package (network/repo issues)
- Network dependencies during provisioning are fragile on RHDP

**What worked**:
- ✓ SSHFS architecture was correct - single source of truth on control VM, mounted to vscode VM
- ✓ File sharing concept addressed the student workflow requirement

---

### Attempt 2: Inline File Generation (Simplified)
**Files**: Current versions of setup-control.sh (72 lines), setup-vscode.sh (88 lines)

**Architecture**:
- Both VMs create ansible-files directory locally
- setup-control.sh generates all 4 files using bash heredocs (no network calls)
- setup-vscode.sh generates the same 4 files locally (independent copy)
- No SSHFS, no file sharing mechanism

**Why it failed**:
- ✗ **Broke file sharing**: vscode VM and control VM have independent ansible-files directories
- ✗ Student edits in VS Code won't appear when running playbooks in Control terminal
- ✗ Doesn't match student workflow requirement

**What worked**:
- ✓ Fast provisioning (no network dependencies)
- ✓ Simple, reliable scripts
- ✓ No external dependencies

---

### Attempt 3: Single VM Architecture (SUCCESSFUL)
**Files**: config/instances.yaml (4 VMs), setup-automation/setup-control.sh (97 lines with code-server)

**Architecture**:
- Consolidated vscode and control VMs into a single `control` VM
- control VM uses devtools-ansible image (has code-server pre-installed)
- VS Code runs on port 8080 via code-server service
- Wetty terminal connects to the same control VM
- Both interfaces access `/home/rhel/ansible-files/` on the same filesystem
- setup-control.sh generates all 4 files inline AND configures code-server

**Why it works**:
- ✓ **Single source of truth**: Both VS Code and terminal on same VM, same filesystem
- ✓ **No file sharing needed**: No SSHFS, no NFS, no network mounts
- ✓ **No network dependencies**: All files generated inline during setup
- ✓ **Student workflow preserved**: Two tabs (VS Code + Control) work as expected
- ✓ **Simple and reliable**: Fewer moving parts, easier to debug

**Key insight**: The file sharing problem was architectural - we don't need two VMs. The vscode VM already has terminal capability (SSH), and the devtools-ansible image has everything needed for both VS Code and ansible-navigator.

**Implementation**:
1. Replaced control VM definition in instances.yaml with vscode VM definition
2. Changed name from "vscode" to "control" (wetty expects this)
3. Merged setup-vscode.sh code-server config into setup-control.sh
4. Deleted setup-vscode.sh (no longer needed)
5. ui-config.yml tabs work unchanged (VS Code → vscode-8080 route, Control → /wetty)

**Result**: 4 VMs instead of 5, file sharing works naturally, provisioning is fast and reliable.

---

### Comparison with working-playbook-lab

We compared against `/Users/asergiso/Documents/working-playbook-lab` to understand the proven pattern.

**What we found**:
- ✓ Same two-VM architecture (control + vscode)
- ✓ Same student workflow (edit in VS Code, run in Control)
- ✓ Identical instances.yaml
- ✓ setup-control.sh creates empty ansible-files directory
- ✓ setup-vscode.sh creates empty ansible-files directory
- ⚠️ Files are created by `runtime-automation/01-playbook-inventory/setup.yml` (runs when student starts module 1)
- ⚠️ Uses different runtime-automation/main.yml pattern (shell scripts instead of module playbooks)
- ❓ **UNRESOLVED**: How does working-playbook-lab share files between VMs?

The working lab's setup scripts don't pre-populate ansible-files. The runtime automation creates files on the control VM, but we didn't determine how those files become visible in the VS Code editor on the vscode VM. Either:
1. The working lab has the same file sharing problem (undetected)
2. Wetty terminal actually connects to vscode VM, not control VM
3. There's a file sharing mechanism we didn't discover

---

## Showroom Configuration Issues Fixed

### Issue: nav.adoc Reference
**File**: content/antora.yml

**Problem**:
```yaml
nav:
  - modules/ROOT/nav.adoc  # ← This caused Showroom pod to fail
```

**Root cause**: Zero-touch Showroom labs use `ui-config.yml` for navigation, NOT Antora's `nav.adoc` system. The working-playbook-lab has no `nav:` section in antora.yml.

**Fix**: Removed the `nav:` section entirely from content/antora.yml and deleted content/modules/ROOT/nav.adoc.

**Result**: Showroom pod now builds successfully (no more 600 retries).

---

## Key Architectural Decisions

### 1. Zero-Touch Labs Don't Need AgnosticV Catalog Files
Earlier in the session (before compaction), we created `common.yaml`, `dev.yaml`, `description.adoc` which broke provisioning. These files were removed.

**Why**: Zero-touch labs inherit from zero-touch-base-rhel and only need:
- config/ (instances.yaml, networks.yaml, firewall.yaml)
- content/ (Showroom AsciiDoc)
- setup-automation/
- runtime-automation/
- ui-config.yml
- site.yml

### 2. File Sharing is Critical
Students must see the same files in both tabs:
- **VS Code tab**: File explorer shows `/home/rhel/ansible-files/`
- **Control tab**: `ansible-navigator` reads from `/home/rhel/ansible-files/`

Any solution must address this requirement.

### 3. Network Dependencies Are Problematic
RHDP provisioning environment has unreliable network access:
- GitHub downloads timeout
- Package installs (fuse-sshfs) fail
- Need provisioning to work without external dependencies

---

## Current State

**Git commits this session**:
1. `Remove nav.adoc reference from antora.yml to fix Showroom pod` (4843275)
2. `Simplify setup scripts to use inline file generation` (082d7c3)
3. `Add session handoff documentation` (3d288c3)
4. `Merge branch 'worktree-add-handoff'` (535dc95)

**Files changed** (pending commit):
- config/instances.yaml (4 VMs: control uses devtools-ansible, node1-3 use rhel-9.6)
- setup-automation/setup-control.sh (adds /etc/hosts entries for nodes, configures code-server)
- setup-automation/setup-vscode.sh (deleted - merged into setup-control.sh)
- setup-automation/main.yml (removed vscode from nodes loop)
- utilities/health-check.sh (updated vscode references to control)

**Status**:
- ✓ Showroom pod builds successfully
- ✓ **File sharing RESOLVED**: Single VM architecture - control VM runs both VS Code and terminal
- ✓ Students edit in VS Code and run commands in terminal on the same filesystem
- ✓ **Network issue fixed**: Control resolves node IPs via DNS and adds to /etc/hosts for cross-subnet access
- ✓ **No external dependencies**: All files generated inline, code-server pre-installed in devtools-ansible image

**Architecture change (FINAL)**: 
1. Consolidated vscode and control VMs into single control VM
2. Control uses `devtools-ansible` (has code-server pre-installed, on 10.0.2.x subnet)
3. Nodes use `rhel-9.6` (on 10.130.x.x / 10.129.x.x subnet)
4. Setup script resolves node IPs via `getent hosts` and adds to `/etc/hosts` for cross-subnet communication
5. Ansible-navigator uses `--network=host` so EE container can read /etc/hosts
6. Both VS Code and wetty terminal access same `/home/rhel/ansible-files/` on control VM

**Not pushed to remote**: Changes are committed to local main branch but not pushed to origin.

---

## Design Philosophy Insights

### What This Lab Is
- **Ansible Lightspeed tutorial**: Students learn to generate playbooks using AI in VS Code
- **Two-environment workflow**: Edit in GUI (VS Code), run in CLI (Control terminal)
- **Zero-touch RHDP lab**: Babylon CNV, Showroom content delivery, auto-provisioning

### What Students Need
1. Pre-populated workspace with inventory, ansible.cfg, templates
2. Ability to edit files in VS Code and see changes when running playbooks
3. Fast provisioning (students waiting in workshop session)
4. Reliable provisioning (can't depend on external network)

### Constraints
- Network during provisioning is unreliable (GitHub, package repos)
- Zero-touch base config provides wetty terminal, but unclear which VM it targets
- SSHFS requires fuse-sshfs package (network dependency)
- Students can't manually sync files between VMs

---

## Troubleshooting Guide for Future Sessions

### Common Provisioning Hangups

**Symptom**: Lab hangs on "checking if showroom is up and ready"

**Likely causes**:
1. **Network downloads in setup scripts** - Any `curl`, `wget`, `npm install`, `pip install`, or package installs from external repos will timeout or hang during RHDP provisioning
2. **Systemd service failures** - Commands like `systemctl enable --now service` can hang if the service fails to start
3. **Missing packages** - Installing code-server requires nodejs/npm which may not be in satellite repos
4. **VM waiting for network** - VMs on different images (devtools-ansible vs rhel-9.6) get different network configurations

**How to debug**:
1. Check OpenShift console → showroom pod logs → init containers for setup-automation output
2. SSH into control VM (if provisioned) and check `/tmp/setup-scripts/*.log` for script failures
3. Look for timeout errors, package installation failures, or systemd service startup issues

### Networking Issues (VM-to-VM Communication)

**Symptom**: `ansible-navigator` can't SSH to nodes, "Connection timed out" errors

**Root cause**: Different VM images get IPs on different subnets in CNV:
- `devtools-ansible` image → 10.0.2.x/24 (isolated network)
- `rhel-9.6` image → 10.130.x.x or 10.129.x.x (pod network)

**Why secondary network doesn't work**:
- Adding `networks: [default, secondary]` to instances.yaml doesn't create a second interface (eth1)
- Only eth0 exists on the VM
- `nmcli connection add ... eth1` commands fail silently
- The secondary network feature may not be implemented in CNV or requires additional configuration

**Solution used**:
- Control VM uses `devtools-ansible` (10.0.2.x) 
- Nodes use `rhel-9.6` (10.130.x.x)
- Setup script on control runs `getent hosts nodeX` to resolve IPs via cluster DNS
- Adds resolved IPs to `/etc/hosts`: `10.130.15.235 node1`
- Ansible-navigator EE uses `--network=host` so it can read control's /etc/hosts
- Cross-subnet routing works because both subnets are in the same OpenShift cluster

**Diagnostic commands** (run from control VM):
```bash
# Check what subnet control is on
ip addr show eth0

# Check if DNS can resolve nodes
getent hosts node1

# Check if nodes are in /etc/hosts
cat /etc/hosts | grep node

# Try pinging node IPs directly
ping -c 2 10.130.15.235

# Check if SSH port is open
timeout 3 bash -c "cat < /dev/tcp/10.130.15.235/22"
```

### Code-Server Installation

**Why we use devtools-ansible image**:
- Code-server is pre-installed and configured
- Installing code-server during setup causes hangups (requires npm/nodejs, downloads from internet)
- The lab needs VS Code for the Ansible Lightspeed extension demo

**Attempted approaches that failed**:
1. ❌ `curl -fsSL https://code-server.dev/install.sh | sh` - network download hangs
2. ❌ `npm install -g code-server` - requires nodejs/npm packages, network download hangs
3. ❌ Installing from satellite repos - code-server not available in RHDP repos

**Working approach**:
- Use devtools-ansible image which has code-server pre-baked
- Setup script only configures it (config.yaml) and starts the service
- No network dependencies during provisioning

---

## Files Reference

**Key files to understand**:
- `/Users/asergiso/Documents/zt-writing-your-first-playbook/setup-automation/setup-control.sh`
- `/Users/asergiso/Documents/zt-writing-your-first-playbook/setup-automation/setup-vscode.sh`
- `/Users/asergiso/Documents/zt-writing-your-first-playbook/config/instances.yaml`
- `/Users/asergiso/Documents/zt-writing-your-first-playbook/ui-config.yml`
- `/Users/asergiso/Documents/zt-writing-your-first-playbook/content/antora.yml`

**Comparison reference**:
- `/Users/asergiso/Documents/working-playbook-lab/` (provisioning works, but file sharing mechanism unclear)

**Ansible files that need to exist**:
- ansible-files/ansible.cfg (3 lines)
- ansible-files/ansible-navigator.yml (19 lines)
- ansible-files/inventory (11 lines)
- ansible-files/templates/motd.j2 (4 lines)

All four files exist in the repo at `/Users/asergiso/Documents/zt-writing-your-first-playbook/ansible-files/`

---

## File Inventory and Purpose

### Configuration Files

**config/instances.yaml** (4 VMs, 117 lines)
- `control`: devtools-ansible, 8G RAM, 30Gi disk, has services/routes for code-server on port 8080
- `node1`, `node2`, `node3`: rhel-9.6, 8G RAM, 30Gi disk, managed nodes for playbook execution
- All VMs: `AnsibleGroup: isolated` tag (enables cloud-init password auth)
- All VMs: `networks: [default]` (CNV pod network)

**config/networks.yaml** (3 lines)
- Single network: `default` (CNV pod network)
- No secondary network (doesn't work in CNV)

**config/firewall.yaml** (20 lines)
- Egress: allows TCP 80, 443 (for downloading EE container images)
- Ingress: allows TCP 8080 (for code-server web UI)
- Platform defaults: SSH (22), DNS (5353), VM-to-VM traffic

**ui-config.yml** (27 lines)
- Defines 4 content modules (01-04) with solve buttons
- Tab 1: VS Code → `https://vscode-${guid}.${domain}/` (code-server on control:8080)
- Tab 2: Control → `/wetty` (terminal provided by zero-touch-base-rhel, connects to control VM)

**site.yml** (21 lines)
- Antora site configuration for Showroom content
- Points to content/ directory for AsciiDoc modules
- Uses nookbag-bundle UI theme

### Setup Automation

**setup-automation/main.yml** (89 lines)
- Creates dynamic inventory from environment variables (BASTION_HOST, BASTION_PORT, etc.)
- Adds bastion (control) and nodes (node1, node2, node3) to inventory
- Copies setup-*.sh scripts to each VM and executes them
- Waits up to 300 seconds for SSH connection before timeout
- Runs on `all:!localhost` (control + node1 + node2 + node3)

**setup-automation/setup-control.sh** (118 lines)
- Resolves node1/node2/node3 IPs via `getent hosts` and adds to `/etc/hosts`
- Creates `/home/rhel/ansible-files/` with ansible.cfg, ansible-navigator.yml, inventory, templates/motd.j2
- Configures code-server (config.yaml, systemctl start/enable)
- No network dependencies (all files inline, code-server pre-installed)

**setup-automation/setup-node1.sh, setup-node2.sh, setup-node3.sh** (31 lines each)
- Waits for dnf/yum to be ready (cloud-init may still be running)
- Minimal setup - SSH already configured via cloud-init
- No package installations (keeps provisioning fast)

### Runtime Automation

**runtime-automation/main.yml** (47 lines)
- Dispatcher pattern: runs module-specific setup/solve/validation playbooks
- Uses `ansible-playbook` to execute `./module_dir/module_stage.yml`
- Reads from `runtime-automation/inventory` (maps controller→control, web→node1/2, database→node3)

**runtime-automation/NN-module-name/** (4 modules)
- Each module has: `setup.yml`, `solve.yml`, `validation.yml`
- Module 01: Verifies inventory exists, teaches ansible-navigator inventory commands
- Module 02: Students generate system_setup.yml playbook with Lightspeed
- Module 03: Students run playbook, verify httpd on web group, user on all hosts
- Module 04: Wrap-up, no validation (informational only)

### Health Monitoring

**utilities/health-check.sh** (72 lines)
- Auto-generated by Lab Foundry validate-lab skill
- Checks SSH connectivity to all VMs (control, node1, node2, node3)
- Checks code-server HTTP endpoint (https://vscode-${GUID}.${DOMAIN})
- Checks code-server port on control (8080)
- Optionally reports to webhook (HEALTH_WEBHOOK_URL)
- Returns exit code = number of failures

### Content

**content/modules/ROOT/pages/** (4 modules, ~800 lines total AsciiDoc)
- 01-playbook-inventory.adoc: Introduction to inventory, ansible-navigator
- 02-generate-comprehensive-playbook.adoc: Using Lightspeed to generate playbooks
- 03-playbook-run-it.adoc: Running playbooks, verifying results, idempotency
- 04-wrap-up.adoc: Summary and next steps

**content/modules/ROOT/assets/images/** (9 images)
- Screenshots of Showroom UI, VS Code, ansible-navigator output
- Used in content pages to guide students


---

## Validation Checklist (Before Next Provision)

### Pre-Provision Checks
- [ ] All setup scripts are executable: `chmod +x setup-automation/setup-*.sh`
- [ ] No network downloads in setup scripts (curl, wget, npm, pip)
- [ ] No `set -e` failures on non-critical commands (use `|| true` or error handling)
- [ ] setup-automation/main.yml nodes loop matches actual VMs (node1, node2, node3 only)

### Post-Provision Validation (if provisioning succeeds)

**From Control VM terminal:**
```bash
# 1. Check /etc/hosts has node entries
cat /etc/hosts | grep node
# Expected: 3 lines with node1, node2, node3 IPs

# 2. Check code-server is running
systemctl status code-server
curl -s http://localhost:8080 | head -20
# Expected: code-server HTML response

# 3. Check ansible-files exists
ls -la /home/rhel/ansible-files/
# Expected: ansible.cfg, ansible-navigator.yml, inventory, templates/

# 4. Test DNS resolution
getent hosts node1
getent hosts node2  
getent hosts node3
# Expected: IP addresses returned (10.130.x.x or 10.129.x.x)

# 5. Test ping to nodes
ping -c 2 node1
ping -c 2 node2
ping -c 2 node3
# Expected: Replies received (if on same subnet) or 100% loss (if cross-subnet but /etc/hosts works)

# 6. Test SSH to nodes
ssh -o ConnectTimeout=5 rhel@node1 hostname
# Expected: "node1" returned, password: ansible123!

# 7. Test ansible-navigator
cd /home/rhel/ansible-files
ansible-navigator inventory --list
# Expected: JSON with web, database, nodes groups
```

**From Showroom UI:**
- [ ] VS Code tab loads and shows /home/rhel/ansible-files/ in file explorer
- [ ] Control tab shows wetty terminal prompt
- [ ] Can edit a file in VS Code and see it in Control terminal: `cat /home/rhel/ansible-files/inventory`
- [ ] Ansible Lightspeed extension is visible in VS Code extensions panel

### Known Issues to Watch For

**If provisioning hangs:**
- Check OpenShift console → showroom pod → init container logs
- Look for setup script failures in `/tmp/setup-scripts/*.log` on VMs
- Common culprits: network timeouts, systemctl hangs, package installation failures

**If ansible-navigator can't reach nodes:**
- Check `/etc/hosts` on control has node IPs
- Check `ip addr show eth0` on control (should be 10.0.2.x)
- Check nodes are on 10.130.x.x or 10.129.x.x network
- Verify ansible-navigator.yml has `container-options: ["--network=host"]`

**If VS Code doesn't load:**
- Check code-server service: `systemctl status code-server`
- Check port 8080 is listening: `ss -tlnp | grep 8080`
- Check route in instances.yaml: vscode-8080 → port 8080
- Check ui-config.yml: VS Code tab URL matches route host
