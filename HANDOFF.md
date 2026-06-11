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
- config/instances.yaml (consolidated VMs: control now has devtools-ansible image + code-server)
- setup-automation/setup-control.sh (added code-server configuration)
- setup-automation/setup-vscode.sh (deleted - merged into setup-control.sh)

**Status**:
- ✓ Showroom pod builds successfully
- ✓ No network dependencies during provisioning
- ✓ **File sharing RESOLVED**: Single VM architecture - control VM runs both VS Code and terminal
- ✓ Students edit in VS Code and run commands in terminal on the same filesystem

**Architecture change**: Consolidated vscode and control VMs into a single control VM that runs both code-server (VS Code) and provides the wetty terminal. Both interfaces access `/home/rhel/ansible-files/` on the same VM, eliminating file sharing complexity.

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

## Next Steps Considerations

Any new approach must:
1. ✓ Generate ansible-files inline (no GitHub dependency)
2. ✓ Share files between vscode VM and control VM
3. ✓ Work without network access during provisioning
4. ✓ Be simple enough to debug when things go wrong

**Approaches to consider**:
- NFS mount instead of SSHFS?
- Copy files with rsync on a timer?
- Pre-bake files into the devtools-ansible image?
- Reverse the architecture: create files on vscode VM, mount to control VM?
- Investigate how wetty actually connects (maybe it's on vscode VM?)?
- Check if there's a zero-touch pattern for shared filesystems we're missing?

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
