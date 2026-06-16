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

## Current State (FINAL SOLUTION - June 2026)

### Attempt 4: Network Routing Fix via Services/Routes (WORKING)
**Commits**: 
- `f693d63` Fix control-to-nodes connectivity by using same image for all VMs
- `91d687c` Restore /etc/hosts workaround for cross-subnet node access
- `103cecb` testing
- `9fdcf1e` Adding routing to hosts

**Problem discovered**:
The initial assumption was wrong - **VM image type does NOT determine subnet assignment**. All VMs using `devtools-ansible` still resulted in:
- Control: `10.0.2.2/24` (isolated network)
- Nodes: `10.130.x.x` (pod network)

**Root cause**: VMs with `services:` and `routes:` definitions get placed on the isolated 10.0.2.x network. VMs without services/routes land on the pod network (10.130.x). This is a CNV provisioning behavior, not related to image type.

**Solution**: Add services/routes to ALL VMs so they all land on the same 10.0.2.x subnet.

**Files changed**:
1. **config/instances.yaml** - Added HTTP services and routes to node1, node2, node3
   - Each node now has `services:` section (HTTP port 80)
   - Each node now has `routes:` section (web access via TLS edge termination)
   - Forces CNV to provision all nodes on same isolated network as control (10.0.2.x)

2. **setup-automation/main.yml** - Moved /etc/hosts configuration to Ansible playbook
   - Added `Gather node IP addresses` play to collect Ansible facts from nodes
   - Added `Configure node hostname resolution on control` play
   - Uses `ansible_default_ipv4.address` from facts (reliable) instead of `getent hosts` (unreliable - returns duplicate IPs in CNV DNS)
   - Populates /etc/hosts on control BEFORE setup scripts run
   - Uses `lineinfile` with regexp to prevent duplicate entries

3. **setup-automation/setup-control.sh** - Removed DNS resolution logic
   - Deleted 18 lines of bash DNS resolution + sleep delays
   - Now just a comment explaining /etc/hosts is handled by main.yml
   - Simpler, cleaner script (back to ~109 lines)

4. **ui-config.yml** - Added wetty tabs for direct node access
   - Students can now SSH directly to node1, node2, node3 via web terminal
   - Useful for debugging connectivity issues

5. **ansible-files/ansible.cfg** - Added SSH connection parameters (retained from earlier fix)
   - `[ssh_connection]` section with 10-second timeout
   - Prevents SSH from hanging on unreachable hosts

6. **ansible-files/inventory** - Added explicit connection variables (retained from earlier fix)
   - `[all:vars]` section with `ansible_user=rhel` and SSH args
   - Documents authentication method for students

**Status**:
- ✓ **File sharing RESOLVED**: Single VM architecture - control VM runs both VS Code and terminal
- ✓ **Network routing RESOLVED**: All VMs on same subnet (10.0.2.x) via services/routes configuration
- ✓ **Hostname resolution RESOLVED**: /etc/hosts populated via Ansible facts (not DNS)
- ✓ Showroom pod builds successfully
- ✓ No external dependencies during provisioning
- ✓ All changes pushed to origin/main
- ⚠️ **Ansible Lightspeed / LiteMaaS**: Configuration wired up (rhcustom provider, bundled v26.6.0 extension, vault-encrypted API key). Auth redirect still fires — open issue.

**Architecture (FINAL)**: 
1. **4 VMs total**: control + node1 + node2 + node3 (all using devtools-ansible image)
2. **All VMs on 10.0.2.x subnet**: Achieved by adding services/routes to all VM definitions
3. **Control VM**: Runs code-server (VS Code) on port 8080 + wetty terminal
4. **Node VMs**: Run HTTP service on port 80 (for routing purposes, forces same subnet)
5. **/etc/hosts populated by Ansible**: Using gathered facts, not DNS (more reliable)
6. **Students access**: VS Code tab (edit) + Control tab (run ansible-navigator) on same filesystem
7. **Ansible Lightspeed**: Backed by LiteMaaS (`https://maas-rhdp.apps.maas.redhatworkshops.io`, model `openai/deepseek-r1-distill-qwen-14b`). Extension v26.6.0 bundled as vsix. API key vault-encrypted in `config/secrets.yaml` (vault ID: `ansiblebu_vault`).

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

**Root cause (CORRECTED)**: Subnet assignment is NOT determined by VM image type. It's determined by whether the VM has `services:` and `routes:` defined in instances.yaml:
- VMs **with** services/routes → 10.0.2.x/24 (isolated network)
- VMs **without** services/routes → 10.130.x.x or 10.129.x.x (pod network)

**Failed approaches**:
1. ❌ **Secondary network**: Adding `networks: [default, secondary]` to instances.yaml doesn't create eth1 interface
2. ❌ **DNS resolution in setup script**: `getent hosts` returns duplicate IPs in CNV DNS (unreliable)
3. ❌ **Image type switching**: All VMs using devtools-ansible still landed on different subnets

**Working solution**:
- Add `services:` and `routes:` to ALL VMs (control + node1/2/3) in instances.yaml
- This forces CNV to provision all VMs on same 10.0.2.x isolated network
- Use Ansible facts (`ansible_default_ipv4.address`) to populate /etc/hosts reliably
- Populate /etc/hosts BEFORE setup scripts run (in setup-automation/main.yml)
- Ansible-navigator EE uses `--network=host` so it can read control's /etc/hosts

**Key learning**: Services/routes in instances.yaml are not just for web access - they also control network placement in CNV.

**Diagnostic commands** (run from control VM):
```bash
# Check what subnet control is on
ip addr show eth0

# Check if nodes are in /etc/hosts (should be populated by main.yml)
cat /etc/hosts | grep node

# Try pinging nodes by hostname
ping -c 2 node1

# Check if SSH port is open
timeout 3 bash -c "cat < /dev/tcp/node1/22"

# Test ansible connectivity
cd /home/rhel/ansible-files
ansible-navigator run -m ping all --mode stdout
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
