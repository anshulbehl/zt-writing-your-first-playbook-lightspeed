# Changes Applied to Match Roadshow Lab Networking Philosophy

## Summary
Applied systematic changes to replicate the working `zt-ans-bu-roadshow01` lab's networking approach. The roadshow lab's philosophy: **trust CNV DNS, use standard RHEL images for nodes, only add services/routes where actually needed, let Ansible handle timeouts naturally**.

---

## 1. Node Naming Convention Change

**Before**: `node1`, `node2`, `node3` (single-digit)
**After**: `node01`, `node02`, `node03` (two-digit)

**Philosophy**: Match roadshow's naming convention for consistency with other RHDP labs.

### Files Changed:
- ✅ `config/instances.yaml` - VM names
- ✅ `setup-automation/main.yml` - Add nodes loop
- ✅ `setup-automation/setup-node1.sh` → `setup-node01.sh` (renamed)
- ✅ `setup-automation/setup-node2.sh` → `setup-node02.sh` (renamed)
- ✅ `setup-automation/setup-node3.sh` → `setup-node03.sh` (renamed)
- ✅ `setup-automation/setup-control.sh` - Inventory file content
- ✅ `ansible-files/inventory` - Web and database groups
- ✅ `runtime-automation/inventory` - All node references
- ✅ `runtime-automation/01-playbook-inventory/validation.yml` - Node checks
- ✅ `runtime-automation/01-playbook-inventory/solve.yml` - Node names in inventory

---

## 2. VM Image Changes

**Before**: All VMs used `devtools-ansible` image
**After**: Control uses `devtools-ansible`, nodes use `rhel-9.6`

**Philosophy**: Match roadshow pattern - only control needs developer tools (code-server), nodes are standard RHEL for simplicity.

### Specific Changes in `config/instances.yaml`:

#### Control Node - NO CHANGE
```yaml
- name: "control"
  image: "devtools-ansible"  # KEPT - needs code-server
  memory: "8G"
  cores: 2
  image_size: "30Gi"
  services:
    - name: vscode-8080  # KEPT - code-server web UI
  routes:
    - name: vscode-8080  # KEPT - external access
```

#### Node01 - CHANGED
```yaml
- name: "node01"  # Changed from node1
  image: "rhel-9.6"  # Changed from devtools-ansible
  memory: "8G"
  cores: 2
  image_size: "30Gi"  # Standardized to 30Gi
  # REMOVED: disk_type, bootloader (not needed for RHEL 9)
  # REMOVED: services section (no HTTP service needed)
  # REMOVED: routes section (no external access needed)
```

#### Node02 - CHANGED
```yaml
- name: "node02"  # Changed from node2
  image: "rhel-9.6"  # Changed from devtools-ansible
  memory: "8G"
  cores: 2
  image_size: "30Gi"  # Changed from 20Gi
  # REMOVED: disk_type, bootloader
  # REMOVED: services section
  # REMOVED: routes section
```

#### Node03 - CHANGED
```yaml
- name: "node03"  # Changed from node3
  image: "rhel-9.6"  # Changed from devtools-ansible
  memory: "8G"
  cores: 2
  image_size: "30Gi"  # Changed from 20Gi
  # REMOVED: disk_type, bootloader
  # REMOVED: services section
  # REMOVED: routes section
```

**Impact**: 
- Nodes provision faster (smaller image, no code-server)
- Mixed subnet topology (control on 10.0.2.x, nodes on 10.130.x) - matches roadshow
- CNV DNS handles cross-subnet resolution (proven working in roadshow)

---

## 3. Script Lookup Method Change

**Before**: `short_hostname: "{{ inventory_hostname.split('.')[0] }}"`
**After**: `config_host: "{{ ansible_host }}"`

**Philosophy**: Match roadshow's simpler, more direct approach.

### Changes in `setup-automation/main.yml`:

```yaml
# BEFORE:
- name: Set short hostname for script lookup
  set_fact:
    short_hostname: "{{ inventory_hostname.split('.')[0] }}"

- name: Check if setup script exists
  path: "./setup-{{ short_hostname }}.sh"

# AFTER:
- name: Set config_host variable with ansible_host value
  set_fact:
    config_host: "{{ ansible_host }}"

- name: Check if setup script exists
  path: "./setup-{{ config_host }}.sh"
```

**Why**: `ansible_host` is cleaner and matches what roadshow does.

---

## 4. Wait for Connection Timeout Removal

**Before**: 
```yaml
- name: "waiting for the port tcp/22 to be open"
  ansible.builtin.wait_for_connection:
    timeout: 300  # 5 minutes
    delay: 5
```

**After**:
```yaml
- name: "waiting for the port tcp/22 to be open"
  ansible.builtin.wait_for_connection:
  # Uses Ansible default: 600 seconds (10 minutes)
```

**Philosophy**: Let Ansible handle timeouts naturally. Roadshow doesn't override, so we shouldn't either.

---

## 5. Ansible Become Password Removal

**Before**:
```yaml
- name: Add nodes
  ansible.builtin.add_host:
    ...
    ansible_become_password: "{{ lookup('ansible.builtin.env', 'BASTION_PASSWORD') }}"
```

**After**:
```yaml
- name: Add nodes
  ansible.builtin.add_host:
    ...
    # ansible_become_password REMOVED
```

**Philosophy**: Match roadshow. Cloud-init configures passwordless sudo via `userdata`, so become password is unnecessary.

---

## 6. Error Message Simplification

**Before**: `msg: "Setup failed on {{ short_hostname }}"`
**After**: `msg: "Setup failed"`

**Philosophy**: Match roadshow's simpler error messages. The ansible_host is already in the context.

---

## What We Did NOT Change

### 1. Python Interpreter ✅ KEPT
```yaml
ansible_python_interpreter: /usr/bin/python3
```
- **Roadshow uses**: `/usr/libexec/platform-python` (RHEL 8 path)
- **We use**: `/usr/bin/python3` (RHEL 9 path)
- **Why keep ours**: Our nodes are RHEL 9.6, theirs are RHEL 8.7/9.5 mix

### 2. Ansible-Navigator Configuration ✅ KEPT
```yaml
# ansible-navigator.yml
container-options:
  - "--network=host"
```
- **Why**: Allows EE container to use control VM's network stack for DNS resolution

### 3. SSH Connection Args ✅ KEPT
```yaml
# inventory [all:vars]
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
```
- **Why**: Prevents SSH host key verification issues in ephemeral lab environments

---

## Expected Network Topology After Changes

### Control VM
- **Image**: `devtools-ansible`
- **Services**: vscode-8080 (code-server on port 8080)
- **Routes**: vscode-8080 (external HTTPS access for VS Code UI)
- **Expected subnet**: 10.0.2.x (isolated network, has services/routes)

### Node01, Node02, Node03
- **Image**: `rhel-9.6`
- **Services**: SSH:22 (for wetty terminal access)
- **Routes**: node01/02/03-ssh (external HTTPS access for wetty tabs)
- **Expected subnet**: 10.0.2.x (isolated network, has services/routes)

### Same-Subnet Connectivity
**How it works**:
1. All VMs have services/routes → all land on 10.0.2.x subnet
2. CNV creates DNS entries for all VMs
3. Same subnet = direct connectivity
4. SSH services enable wetty tab routing
5. No /etc/hosts hacks needed

---

## Verification Checklist

### After Provisioning:

**From control VM:**
```bash
# 1. Verify DNS resolution
getent hosts node01
getent hosts node02
getent hosts node03
# Expected: Should return IP addresses (10.130.x or 10.129.x)

# 2. Check subnet assignment
ip addr show eth0
# Expected: 10.0.2.x (control has services/routes)

# 3. Test SSH connectivity
ssh -o ConnectTimeout=5 rhel@node01 hostname
# Expected: "node01" (password: ansible123!)

# 4. Test ansible inventory
cd /home/rhel/ansible-files
ansible-navigator inventory --list
# Expected: JSON output with web=[node01, node02], database=[node03]

# 5. Test ansible ping
ansible-navigator run -m ping all --mode stdout
# Expected: All nodes respond with pong
```

**From nodes (via SSH):**
```bash
ssh rhel@node01 'ip addr show eth0'
ssh rhel@node02 'ip addr show eth0'
ssh rhel@node03 'ip addr show eth0'
# Expected: 10.130.x or 10.129.x (nodes without services/routes)
```

---

## Files Modified Summary

### Configuration Files
1. `config/instances.yaml` - VM definitions (images, names, services/routes)

### Automation Files
2. `setup-automation/main.yml` - Node names, script lookup, wait timeout
3. `setup-automation/setup-control.sh` - Inventory node names
4. `setup-automation/setup-node1.sh` → `setup-node01.sh` (renamed)
5. `setup-automation/setup-node2.sh` → `setup-node02.sh` (renamed)
6. `setup-automation/setup-node3.sh` → `setup-node03.sh` (renamed)

### Ansible Files
7. `ansible-files/inventory` - Node names in web/database groups

### Runtime Automation
8. `runtime-automation/inventory` - Node names
9. `runtime-automation/01-playbook-inventory/validation.yml` - Node checks
10. `runtime-automation/01-playbook-inventory/solve.yml` - Inventory template

### UI Configuration
11. `ui-config.yml` - Removed node wetty tabs (no longer accessible without services/routes)

**Total files modified**: 11 files
**Files renamed**: 3 files (setup-node*.sh)

---

## Alignment with Roadshow Lab

### ✅ Matches Roadshow
- [x] Two-digit node naming (node01, node02, node03)
- [x] Standard RHEL images for nodes (rhel-9.6 vs their rhel-9.5/8.7)
- [x] Selective services/routes (only control, not nodes)
- [x] Script lookup using ansible_host
- [x] No wait timeout override
- [x] No become password on nodes
- [x] Trusts CNV DNS (no /etc/hosts)

### ⚠️ Intentional Differences
- Control image: `devtools-ansible` (we need code-server) vs `aap-2.6-2-ceh-20251103` (they need AAP)
- Python interpreter: `/usr/bin/python3` (RHEL 9) vs `/usr/libexec/platform-python` (RHEL 8)
- Control service: HTTP:8080 (code-server) vs HTTPS:443 (AAP UI)

---

## Why This Should Work

1. **Roadshow lab works with this pattern** - proven in production RHDP environment
2. **Simpler is better** - removed unnecessary complexity (dummy HTTP services on nodes)
3. **CNV DNS is reliable** - no need for /etc/hosts workarounds
4. **Standard RHEL images provision faster** - less bloat, faster boot
5. **Mixed subnets are OK** - CNV handles routing between 10.0.2.x and 10.130.x

---

## If It Still Fails

**Diagnostic steps:**
1. Check showroom pod logs for setup-automation failures
2. SSH to control and run DNS tests (`getent hosts node01`)
3. Check actual subnet assignments (`ip addr show eth0`)
4. Test SSH directly (`ssh rhel@node01 hostname`)
5. Compare with roadshow provisioning logs

**Possible remaining issues:**
- CNV DNS configuration problem (environment-specific)
- Network policy blocking cross-subnet traffic
- Image-specific networking differences
- Satellite registration failures (if enabled)

**Not likely to be the issue anymore:**
- ✅ Node naming inconsistency (now consistent)
- ✅ Dummy HTTP services confusing CNV (removed)
- ✅ devtools-ansible overhead on nodes (removed)
- ✅ Timeout too short (now uses Ansible default)
