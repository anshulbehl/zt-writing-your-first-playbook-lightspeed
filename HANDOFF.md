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
- **4 VMs total**:
  - `control` - devtools-ansible image, runs code-server (VS Code) on port 8080 + wetty terminal, hosts the ansible-files workspace
  - `node1`, `node2`, `node3` - RHEL 9.6 managed nodes (SSH only, no UI tabs)

### Student Workflow
Students interact with two tabs in the Showroom UI:
1. **VS Code tab** → code-server running on control VM at port 8080
   - Students write/edit playbooks here
   - Ansible Lightspeed extension generates code
   - File explorer shows `/home/rhel/ansible-files/`

2. **Control tab** → wetty terminal (provided by zero-touch-base-rhel)
   - Students run `ansible-navigator` commands here
   - Reads from `/home/rhel/ansible-files/` on control VM

Both tabs access the same filesystem on the same VM — no file sharing needed.

### LLM Backend
- **Endpoint**: `https://maas-rhdp.apps.maas.redhatworkshops.io/v1` (LiteMaaS)
- **Model**: `gpt-oss-120b` (120B parameters, 33k context window)
- **API key**: Vault-encrypted in `config/secrets.yaml` (vault ID: `ansiblebu_vault`, password: `4ns1bl3v4ult!`)
- **Previous model**: `openai/deepseek-r1-distill-qwen-14b` (14B) — too small, produced non-compliant YAML

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
- config/ (instances.yaml, networks.yaml, firewall.yaml, secrets.yaml)
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

4. **ansible-files/ansible.cfg** - Added SSH connection parameters (retained from earlier fix)
   - `[ssh_connection]` section with 10-second timeout
   - Prevents SSH from hanging on unreachable hosts

5. **ansible-files/inventory** - Added explicit connection variables (retained from earlier fix)
   - `[all:vars]` section with `ansible_user=rhel` and SSH args
   - Documents authentication method for students

**Status**:
- ✓ **File sharing RESOLVED**: Single VM architecture - control VM runs both VS Code and terminal
- ✓ **Network routing RESOLVED**: All VMs on same subnet (10.0.2.x) via services/routes configuration
- ✓ **Hostname resolution RESOLVED**: /etc/hosts populated via Ansible facts (not DNS)
- ✓ Showroom pod builds successfully
- ✓ No external dependencies during provisioning
- ✓ All changes pushed to origin/main
- ✓ **Ansible Lightspeed / LiteMaaS**: Working. Bundled patched v26.6.0 extension with rhcustom provider, vault-encrypted API key.

**Architecture (FINAL)**: 
1. **4 VMs total**: control + node1 + node2 + node3 (control uses devtools-ansible, nodes use rhel-9.6)
2. **All VMs on 10.0.2.x subnet**: Achieved by adding services/routes to all VM definitions
3. **Control VM**: Runs code-server (VS Code) on port 8080 + wetty terminal
4. **Node VMs**: Run SSH service on port 22 (services/routes force same subnet placement), no UI tabs
5. **/etc/hosts populated by Ansible**: Using gathered facts, not DNS (more reliable)
6. **Students access**: VS Code tab (edit) + Control tab (run ansible-navigator) on same filesystem
7. **Ansible Lightspeed**: Backed by LiteMaaS (`https://maas-rhdp.apps.maas.redhatworkshops.io/v1`, model `gpt-oss-120b`). Extension v26.6.0 bundled as patched vsix (`ms-python.vscode-python-envs` dependency removed for code-server 1.99.3 compatibility). API key vault-encrypted in `config/secrets.yaml` (vault ID: `ansiblebu_vault`).

---

## Ansible Extension Patching (setup-automation/patch_prompts.py)

The extension's bundled JavaScript is patched at provisioning time to customize LLM behavior and fix compatibility issues. The patch script applies 5 modifications:

### Patch 1: Playbook prompt lint rules
Appends ansible-lint compliance rules to the playbook generation system prompt (after `You answer with just an Ansible playbook.`).

### Patch 2: Role prompt rewrite
Replaces the default role prompt (which only generates `tasks/main.yml`) with a comprehensive prompt that produces a YAML mapping with three top-level keys: `tasks`, `handlers`, `vars`. Includes the same lint rules.

### Patch 3: Multi-file role parser
Replaces the single-file builder (`files = [{file_type: "task"}]`) with a regex splitter that parses the YAML mapping output into separate files (`tasks/main.yml`, `handlers/main.yml`, `vars/main.yml`). Falls back to tasks-only if the LLM ignores the mapping format.

**Key insight**: `cleanAnsibleOutput()` does `yaml.load()` then `yaml.dump()` — this strips YAML comments (so `### FILE:` markers won't work) but preserves mapping structure. The YAML mapping approach survives this processing.

### Patch 4: Outline generation fix
The `generateOutlineFromRole` function expects a YAML array but receives a mapping. Patched to extract `parsed.tasks` when the input is a mapping, so the step review on wizard page 2 shows task names.

### Patch 5: File-exists check disabled
`if (await fileExists(fileUri))` → `if (false && fileExists(fileUri))` — prevents "File already exists" error spam when re-generating roles with the same name.

### Lint rules (LINT_RULES constant)
- Always use `ansible.builtin.dnf`, never apt
- Always use `state: present`, never `state: latest`
- Always set `mode:` on file/template/copy tasks
- Human-readable handler names ("Restart Apache", not snake_case)
- `true`/`false` booleans, never `yes`/`no`
- Only include explicitly requested parameters
- Include `notify:` with exact handler name
- Prefix variable names with role name (e.g. `system_setup_user_name`)
- Trailing newline on YAML files

---

## Content Structure (6 Modules)

| # | Slug | Title | solveButton | Validation |
|---|------|-------|-------------|------------|
| 01 | `01-playbook-inventory` | Meet Your Automation Coding Assistant | true | No-op (introductory) |
| 02 | `02-generate-comprehensive-playbook` | Generate a Comprehensive Playbook | true | Checks system_setup.yml structure |
| 03 | `03-understand-the-playbook` | Understand Your Playbook | false | No-op (informational) |
| 04 | `04-playbook-run-it` | Run and Verify the Playbook | true | Checks user, httpd, MOTD on nodes |
| 05 | `05-generate-roles` | Convert Your Playbook to a Role | true | Checks roles/ dir exists |
| 06 | `06-wrap-up` | Wrap-Up and Next Steps | false | No-op (informational) |

### Collection for Role Generation
The extension's `CollectionFinder` requires a `galaxy.yml` to provide a target for "Generate a Role". Created at provisioning time by `setup-control.sh`:
- `ansible-files/galaxy.yml` — namespace: `lab`, name: `system_automation`
- `ansible-files/README.md` — required by Galaxy, brief file listing
- `ansible-files/roles/` — empty directory for generated roles

---

## Runtime Automation

### Dispatch Architecture

**runtime-automation/main.yml** (47 lines)
- Dispatcher pattern: receives `module_dir` and `module_stage` as extra vars from the Showroom platform
- Play 1: Creates inventory from env vars (BASTION_HOST, etc.)
- Play 2: Runs on `localhost`, calls `ansible-playbook ./{{ module_dir }}/{{ module_stage }}.yml`

**runtime-automation/NN-module-name/** (6 modules)
- Each module has: `setup.yml`, `solve.yml`, `validate.yml`
- `module_stage` values sent by the platform: `setup`, `solve`, `validate`

### KNOWN ISSUE: Validation not triggering on "Next" button press

**Status**: UNRESOLVED. Setup and solve work correctly, but pressing "Next" does not trigger validation.

**Investigation findings**:
- The standard RHDP zero-touch pattern (zt-satellite-basics, zt-openscap, etc.) uses shell scripts named `{stage}-{hostname}.sh` (e.g., `solve-satellite.sh`, `validate-rhel.sh`)
- The standard `main.yml` dispatcher runs on `all:!localhost`, SSHes into each host, and executes `./{{ module_dir }}/{{ module_stage }}-{{ config_host }}.sh`
- This lab's `main.yml` runs on `localhost` and calls `ansible-playbook` as a subprocess — unconventional but works for setup/solve
- Files were renamed from `validation.yml` → `validate.yml` to match the platform's `module_stage=validate` value — this alone did not fix the issue
- The remaining theory: the platform runner may expect play 2 to target a remote host (`all:!localhost`), not `localhost`. When the play runs on localhost, the runner may not report results back to the UI correctly for the validate stage.

**Possible fix**: Rewrite `main.yml` to match the standard dispatcher structure — play 2 on `all:!localhost` (the bastion host), running a thin shell wrapper that calls `ansible-playbook` on the remote host. The Ansible playbooks themselves would stay unchanged.

**Alternative**: Create thin shell script wrappers (e.g., `validate-control.sh`) that call `ansible-playbook` against the existing playbooks, and use the standard `main.yml` dispatcher pattern.

### Grading Details

**Module 01** — No-op validation (introductory, no deliverables)
**Module 02** — Validates `system_setup.yml` exists and contains required sections (hosts, become, vars, user_name, when conditional, handlers, template task)
**Module 03** — No-op (informational walkthrough)
**Module 04** — Most comprehensive validation:
- Play 1 (`hosts: all`): checks user `padawan` exists, MOTD contains hostname
- Play 2 (`hosts: web`): checks httpd installed and running
- Play 3 (`hosts: database`): checks httpd is NOT installed (conditional verification)
**Module 05** — Checks `roles/` directory exists with at least one subdirectory
**Module 06** — No-op (wrap-up)

---

## Design Philosophy Insights

### What This Lab Is
- **Ansible Lightspeed tutorial**: Students learn to generate playbooks and roles using AI in VS Code
- **Two-environment workflow**: Edit in GUI (VS Code), run in CLI (Control terminal)
- **Zero-touch RHDP lab**: Babylon CNV, Showroom content delivery, auto-provisioning

### What Students Need
1. Pre-populated workspace with inventory, ansible.cfg, templates, galaxy.yml
2. Ability to edit files in VS Code and see changes when running playbooks
3. Fast provisioning (students waiting in workshop session)
4. Reliable provisioning (can't depend on external network)

### Constraints
- Network during provisioning is unreliable (GitHub, package repos)
- Zero-touch base config provides wetty terminal, but unclear which VM it targets
- SSHFS requires fuse-sshfs package (network dependency)
- Students can't manually sync files between VMs
- Extension's "Explain Playbook" feature uses `createWebviewPanel` with `ViewColumn.Beside`, which doesn't work in code-server 1.99.3 — removed from all modules

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

### Ansible Extension Compatibility

**Problem**: The devtools-ansible image ships code-server 1.99.3 with Ansible extension v25.7.0. The `rhcustom` provider (needed for LiteMaaS/Lightspeed without Red Hat SSO) was added in v26.3.4, but every version from v26.3.0+ adds `ms-python.vscode-python-envs` as an `extensionDependency`, which is not compatible with code-server 1.99.3.

**Symptoms if wrong version is used**:
- v25.7.0 (too old): "You must be logged in to use Ansible Lightspeed" — doesn't know about `rhcustom`, always demands Red Hat SSO OAuth
- v26.6.0 (unpatched): "Cannot activate the 'Ansible' extension because it depends on the 'Python Environments' extension" — `ms-python.vscode-python-envs` can't install on code-server 1.99.3

**Working solution**: Patch the v26.6.0 vsix to remove `ms-python.vscode-python-envs` from `extensionDependencies` in `extension/package.json`. The dependency is for Python environment detection, not core Lightspeed/rhcustom functionality. Steps:
```bash
unzip -q ansible-26.6.0.vsix -d vsix-contents
# Edit vsix-contents/extension/package.json:
#   Remove "ms-python.vscode-python-envs" from extensionDependencies
#   Keep "ms-python.python" and "redhat.vscode-yaml"
cd vsix-contents && zip -qr ../ansible-26.6.0.vsix .
```
The bundled vsix at `setup-automation/ansible-26.6.0.vsix` is already patched.

---

## Content Instruction Updates (June 2026)

### Overview
Updated all module instruction files to align with actual lab behavior and correct mismatches between what students are told to do vs what actually happens during provisioning and validation.

### Key Content Changes

#### 1. Terminology Updates
**Changed**: All references to "Lightspeed" in user-facing content
**To**: "Automation Coding Assistant" or "Red Hat Ansible VS Code extension"
**Reason**: Product rebranding; emphasized that this lab is about the Ansible VS Code extension

#### 2. Pre-Configuration Accuracy
**Issue**: Module 01 Task 1 told students to "Connect to Lightspeed" via Command Palette
**Reality**: `setup-control.sh` pre-configures Lightspeed with LiteMaaS endpoint, no manual connection needed
**Fix**: Changed to verify extension is installed (check left sidebar) instead of connecting

#### 3. Prescriptive Prompts for Validation
**Issue**: Module 02 Task 1 provided a "starter prompt" students could customize
**Problem**: `validate.yml` checks for exact string matches like `when: inventory_hostname in groups['web']` and `handlers:`
**Result**: Students could generate functionally correct playbooks that fail validation due to wording differences
**Fix**: Made the prompt prescriptive with explicit requirements:
- Exact conditional syntax: `when: inventory_hostname in groups['web']`
- Handler requirement explicitly stated
- Module family preference: `ansible.builtin`

#### 4. Removed Explain Feature References
**Issue**: Extension's "Explain Playbook" uses `createWebviewPanel` with `ViewColumn.Beside`, which doesn't work in code-server 1.99.3
**Fix**: Removed all Explain tasks from modules 01 and 02. Replaced with Module 03 (hand-written walkthrough) for the same educational purpose.

#### 5. Added Module 03: Understand Your Playbook
New informational module that walks through the generated `system_setup.yml` section by section — play header, variables, tasks/conditionals, templates, handlers. No solve/validate needed.

#### 6. Added Module 05: Convert Your Playbook to a Role
New hands-on module using the extension's Generate Role feature. Students provide a prompt, set the role name to `system_setup`, select the `lab.system_automation` collection, and review the generated role structure.

#### 7. Module renumbering
- Original: 01 (inventory) → 02 (generate) → 03 (run) → 04 (wrap-up)
- Current: 01 (inventory) → 02 (generate) → 03 (understand) → 04 (run) → 05 (roles) → 06 (wrap-up)

### Validation Compatibility
All instruction changes ensure student-generated content passes existing validation scripts:
- `runtime-automation/02-generate-comprehensive-playbook/validate.yml` - playbook structure and required sections
- `runtime-automation/04-playbook-run-it/validate.yml` - user creation, httpd installation, motd deployment
- `runtime-automation/05-generate-roles/validate.yml` - role directory exists

---

## Files Reference

### Configuration Files

**config/instances.yaml** (4 VMs, ~140 lines)
- `control`: devtools-ansible, 8G RAM, 30Gi disk, has services/routes for code-server on port 8080
- `node1`, `node2`, `node3`: rhel-9.6, 8G RAM, 30Gi disk, managed nodes with SSH services/routes (port 22) to force same-subnet placement

**config/networks.yaml** (3 lines) — Single network: `default` (CNV pod network)

**config/firewall.yaml** (20 lines) — Egress TCP 80/443, Ingress TCP 8080

**config/secrets.yaml** — Vault-encrypted LiteMaaS API key for gpt-oss-120b

**ui-config.yml** (~33 lines)
- Defines 6 content modules with solve buttons
- Tab 1: VS Code → `https://vscode-${guid}.${domain}/` (code-server on control:8080)
- Tab 2: Control → `/wetty` (terminal, connects to control VM)
- Node tabs removed (students SSH into nodes from Control tab, no direct access needed)

**site.yml** (21 lines) — Antora site config, nookbag-bundle v0.0.3 UI theme

### Setup Automation

**setup-automation/main.yml** (~148 lines)
- Creates dynamic inventory from environment variables
- Gathers node IPs via Ansible facts, populates /etc/hosts on control
- Copies setup scripts to VMs and executes them
- Copies bundled Ansible extension vsix to control VM
- Loads vault-encrypted secrets and passes to setup scripts

**setup-automation/setup-control.sh** (~195 lines)
- Configures SSH defaults for node access
- Creates `/home/rhel/ansible-files/` with ansible.cfg, ansible-navigator.yml, inventory, templates/motd.j2
- Creates `galaxy.yml`, `README.md`, and `roles/` directory for collection/role generation
- Configures Ansible Lightspeed with LiteMaaS endpoint (rhcustom provider, API key, model `gpt-oss-120b`)
- Installs patched Ansible extension v26.6.0 vsix
- Configures and starts code-server

**setup-automation/patch_prompts.py** (~112 lines)
- Patches extension.js at provisioning time (5 patches, see "Ansible Extension Patching" section above)

**setup-automation/ansible-26.6.0.vsix** (9.7MB) — Patched Ansible extension vsix

**setup-automation/setup-node{1,2,3}.sh** (31 lines each) — Minimal node setup (wait for dnf)

### Runtime Automation

**runtime-automation/main.yml** (47 lines) — Dispatcher (see "Dispatch Architecture" above)

**runtime-automation/inventory** — Maps controller→control, web→node1/2, database→node3

**runtime-automation/NN-module-name/** (6 modules)
- Each module has: `setup.yml`, `solve.yml`, `validate.yml`

### Content

**content/modules/ROOT/pages/** (6 modules, ~1200 lines total AsciiDoc)
- 01-playbook-inventory.adoc: Introduction to inventory, ansible-navigator
- 02-generate-comprehensive-playbook.adoc: Using Lightspeed to generate playbooks
- 03-understand-the-playbook.adoc: Hand-written playbook walkthrough
- 04-playbook-run-it.adoc: Running playbooks, verifying results, idempotency
- 05-generate-roles.adoc: Using Generate Role feature, role structure
- 06-wrap-up.adoc: Summary and next steps

### Health Monitoring

**utilities/health-check.sh** (72 lines) — Checks SSH to all VMs, code-server endpoint, port 8080

---

## Validation Checklist (Before Next Provision)

### Pre-Provision Checks
- [ ] All setup scripts are executable: `chmod +x setup-automation/setup-*.sh`
- [ ] No network downloads in setup scripts (curl, wget, npm, pip)
- [ ] No `set -e` failures on non-critical commands (use `|| true` or error handling)
- [ ] setup-automation/main.yml nodes loop matches actual VMs (node1, node2, node3 only)
- [ ] `config/secrets.yaml` has valid vault-encrypted API key for gpt-oss-120b

### Post-Provision Validation (if provisioning succeeds)

**From Control VM terminal:**
```bash
# 1. Check /etc/hosts has node entries
cat /etc/hosts | grep node

# 2. Check code-server is running
systemctl status code-server
curl -s http://localhost:8080 | head -20

# 3. Check ansible-files exists with all required files
ls -la /home/rhel/ansible-files/
# Expected: ansible.cfg, ansible-navigator.yml, inventory, templates/, galaxy.yml, README.md, roles/

# 4. Test ansible connectivity
cd /home/rhel/ansible-files
ansible-navigator run -m ping all --mode stdout

# 5. Test Lightspeed model connectivity
# Open VS Code, create a new .yml file, type "- name: " and check for completions
```

**From Showroom UI:**
- [ ] VS Code tab loads and shows /home/rhel/ansible-files/ in file explorer
- [ ] Control tab shows wetty terminal prompt
- [ ] Can edit a file in VS Code and see it in Control terminal
- [ ] Ansible extension is visible in VS Code extensions panel
- [ ] "Generate a Playbook" button works in Ansible extension panel
- [ ] "Generate a Role" button works and shows collection selection

### Known Issues to Watch For

**If provisioning hangs:**
- Check OpenShift console → showroom pod → init container logs
- Look for setup script failures in `/tmp/setup-scripts/*.log` on VMs

**If ansible-navigator can't reach nodes:**
- Check `/etc/hosts` on control has node IPs
- Check `ip addr show eth0` on control (should be 10.0.2.x)
- Verify ansible-navigator.yml has `container-options: ["--network=host"]`

**If validation doesn't trigger on Next button:**
- See "KNOWN ISSUE" in Runtime Automation section
- Setup and solve work; validate dispatch needs main.yml restructuring
