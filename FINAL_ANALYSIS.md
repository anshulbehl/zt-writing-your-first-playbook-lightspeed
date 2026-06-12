# Final Network Analysis: Writing Your First Playbook Lab

## Problem Statement

The `zt-writing-your-first-playbook` lab fails to provision or has network connectivity issues between the control node and managed nodes (node1, node2, node3). We need to identify why, using the working `zt-ans-bu-roadshow01` lab as a reference.

---

## Key Finding: The /etc/hosts Solution Was WRONG

### What HANDOFF.md Claims
HANDOFF.md (lines 180-244) documents a "working" solution where:
1. /etc/hosts configuration was added to setup-automation/main.yml
2. Ansible gathers facts from nodes to get their IPs
3. These IPs are written to control's /etc/hosts
4. Status: "✓ Network routing RESOLVED"

### Reality Check
- Commit `9fdcf1e` added this /etc/hosts configuration
- Commit `aaaac02` ("Fixed claude being bad boy") **removed it** because **the lab wouldn't provision**
- **The reference lab `zt-ans-bu-roadshow01` does NOT use /etc/hosts configuration**
- Reference lab's main.yml has `gather_facts: false` everywhere
- Reference lab works with DNS hostname resolution, not /etc/hosts

**Conclusion**: The /etc/hosts approach was a dead end. Alex was right to remove it.

---

## Architecture Comparison

### Network Topology

#### zt-ans-bu-roadshow01 (WORKING)
```
control:       aap-2.6-2-ceh-20251103, services/routes for HTTPS:443   → 10.0.2.x subnet
node01:        rhel-9.5, NO services, NO routes                        → 10.130.x subnet (pod network)
node02:        rhel-8.7, services/routes for HTTP:80                   → 10.0.2.x subnet
node03:        rhel-9.5, services/routes for HTTP:80                   → 10.0.2.x subnet
```

**Mixed subnets but it works!** This suggests:
1. CNV DNS resolves hostnames across subnets
2. OR the AAP control image has special networking capabilities
3. OR there's routing between 10.0.2.x and 10.130.x networks

#### zt-writing-your-first-playbook (BROKEN)
```
control:       devtools-ansible, services/routes for HTTP:8080  → 10.0.2.x subnet
node1:         devtools-ansible, services/routes for HTTP:80    → 10.0.2.x subnet  
node2:         devtools-ansible, services/routes for HTTP:80    → 10.0.2.x subnet
node3:         devtools-ansible, services/routes for HTTP:80    → 10.0.2.x subnet
```

**All on same subnet but doesn't work!** This suggests the problem is NOT subnet mismatch.

---

## Script Naming Convention Differences

### zt-ans-bu-roadshow01 Approach
```yaml
# main.yml uses ansible_host variable
- name: Set config_host variable with ansible_host value
  set_fact:
    config_host: "{{ ansible_host }}"

- name: Check if setup script exists
  path: "./setup-{{ config_host }}.sh"  # Looks for setup-control.sh, setup-node01.sh, etc.
```

Scripts are named: `setup-control.sh`, `setup-node01.sh`, `setup-node02.sh`, `setup-node03.sh`

### zt-writing-your-first-playbook Approach
```yaml
# main.yml uses inventory_hostname split
- name: Set short_hostname for script lookup
  set_fact:
    short_hostname: "{{ inventory_hostname.split('.')[0] }}"

- name: Check if setup script exists
  path: "./setup-{{ short_hostname }}.sh"  # Looks for setup-control.sh, setup-node1.sh, etc.
```

Scripts are named: `setup-control.sh`, `setup-node1.sh`, `setup-node2.sh`, `setup-node3.sh`

**Status**: Both approaches are valid. Node naming (node1 vs node01) is just a convention difference.

---

## Node Naming: node1 vs node01

### Consistency Check for zt-writing-your-first-playbook

| File/Location | Node Names | Status |
|---------------|------------|--------|
| instances.yaml VM definitions | `node1`, `node2`, `node3` | ✓ |
| main.yml Add nodes loop | `node1`, `node2`, `node3` | ✓ |
| Setup script filenames | `setup-node1.sh`, `setup-node2.sh`, `setup-node3.sh` | ✓ |
| ansible-files/inventory | `node1`, `node2` (web), `node3` (database) | ✓ |
| setup-control.sh inventory | `node1`, `node2`, `node3` | ✓ |

**Conclusion**: Naming is FULLY CONSISTENT. This is not the problem.

---

## Actual Differences That Matter

### 1. Python Interpreter Path

**Reference lab (RHEL 8.7 + RHEL 9.5)**:
```yaml
ansible_python_interpreter: /usr/libexec/platform-python  # RHEL 8 path
```

**Our lab (all RHEL 9.6 via devtools-ansible)**:
```yaml
ansible_python_interpreter: /usr/bin/python3  # RHEL 9 path
```

**Impact**: Our lab is correct for RHEL 9. Not the problem.

---

### 2. VM Images

**Reference lab**:
- Control: `aap-2.6-2-ceh-20251103` (Ansible Automation Platform 2.6 image, 32G RAM, 4 cores)
- Nodes: Mix of `rhel-9.5` and `rhel-8.7` (standard RHEL images, 8G RAM)

**Our lab**:
- All VMs: `devtools-ansible` (developer tools + code-server pre-installed, 8G RAM)

**Why devtools-ansible for all VMs?**
- Control needs code-server (VS Code) → devtools-ansible makes sense
- Nodes don't need code-server → could use standard rhel-9.6 instead
- HANDOFF.md claims using same image for all VMs ensures same subnet (FALSE - subnet determined by services/routes)

**Hypothesis**: Using devtools-ansible for nodes might be causing issues:
- Larger image size → slower provisioning
- Pre-installed services might conflict
- Different network configuration defaults

---

### 3. Services/Routes Strategy

**Reference lab**: Selective services/routes
- control: HTTPS (AAP web UI)
- node01: NONE (just SSH)
- node02: HTTP (demo web server)
- node03: HTTP (demo web server)

**Our lab**: Universal services/routes
- control: HTTP:8080 (code-server)
- node1: HTTP:80 (added to force same subnet)
- node2: HTTP:80 (added to force same subnet)
- node3: HTTP:80 (added to force same subnet)

**Why this difference exists**: HANDOFF.md strategy to force all VMs onto 10.0.2.x subnet.

**Why it might be wrong**: 
- Reference lab proves cross-subnet connectivity works
- Adding dummy HTTP services might confuse CNV provisioning
- Nodes don't actually run HTTP servers, so port 80 isn't listening

---

### 4. Wait for Connection Timeout

**Reference lab**:
```yaml
- name: "waiting for the port tcp/22 to be open"
  ansible.builtin.wait_for_connection:
  # No timeout specified → uses Ansible default (600 seconds)
```

**Our lab**:
```yaml
- name: "waiting for the port tcp/22 to be open"
  ansible.builtin.wait_for_connection:
    timeout: 300  # 5 minutes
    delay: 5
```

**Impact**: Our lab might timeout too early if provisioning is slow.

---

## Root Cause Hypothesis

### Theory 1: devtools-ansible Image on Nodes is Unnecessary
**Evidence**:
- Reference lab uses standard RHEL images for nodes → works
- Our lab uses devtools-ansible for nodes → fails
- Nodes don't need code-server or developer tools

**Test**: Change node1, node2, node3 to use `rhel-9.6` image instead of `devtools-ansible`

---

### Theory 2: Dummy HTTP Services Breaking DNS
**Evidence**:
- Reference lab: Only nodes that ACTUALLY run HTTP have services/routes
- Our lab: All nodes have HTTP services/routes even though HTTP isn't running
- CNV might be setting up special DNS/routing for services that don't exist

**Test**: Remove services/routes from node1, node2, node3 (only keep on control)

---

### Theory 3: ansible-navigator Container Networking
**Evidence**:
- Our ansible-navigator.yml has `container-options: ["--network=host"]`
- This makes the EE container use host (control VM) network stack
- If control VM can't resolve node hostnames via DNS, neither can the container

**Test**: Verify DNS resolution works from control VM:
```bash
# From control VM:
getent hosts node1
ping -c 2 node1
ssh rhel@node1 hostname
```

If these fail, the problem is control→node DNS, not ansible-navigator configuration.

---

## Recommended Fix Strategy

### Phase 1: Simplify to Match Reference Lab Pattern

**Change 1: Use Standard RHEL Images for Nodes**
```yaml
# config/instances.yaml

# Keep control as-is (needs code-server)
- name: "control"
  image: "devtools-ansible"  # KEEP
  services: [...] # KEEP code-server on 8080
  routes: [...]   # KEEP

# Change nodes to standard RHEL
- name: "node1"
  image: "rhel-9.6"  # CHANGE from devtools-ansible
  # REMOVE services section
  # REMOVE routes section
  
- name: "node2"
  image: "rhel-9.6"  # CHANGE from devtools-ansible
  # REMOVE services section
  # REMOVE routes section

- name: "node3"  
  image: "rhel-9.6"  # CHANGE from devtools-ansible
  # REMOVE services section
  # REMOVE routes section
```

**Rationale**: Match the reference lab's proven architecture.

---

**Change 2: Remove Wait Timeout (Use Ansible Default)**
```yaml
# setup-automation/main.yml
- name: "waiting for the port tcp/22 to be open"
  ansible.builtin.wait_for_connection:
  # Remove timeout: 300 and delay: 5
```

**Rationale**: Let Ansible wait the full 600 seconds like the reference lab does.

---

**Change 3: Verify Inventory Naming**

Current setup-control.sh creates this inventory:
```ini
[web]
node1
node2

[database]
node3
```

This matches:
- instances.yaml VM names ✓
- main.yml loop ✓
- DNS hostnames that will be created ✓

**No changes needed.**

---

### Phase 2: Test DNS Resolution

After Phase 1 changes, provision the lab and SSH to control to test:

```bash
# Test 1: DNS resolution
getent hosts node1
getent hosts node2  
getent hosts node3
# Expected: Should return IP addresses

# Test 2: Ping
ping -c 2 node1
# Expected: Should get replies (if same subnet) or "Destination Host Unreachable" (if different subnet but DNS works)

# Test 3: SSH
ssh -o ConnectTimeout=5 rhel@node1 hostname
# Expected: Should return "node1" (password: ansible123!)

# Test 4: Ansible from control (not in EE)
cd /home/rhel
ansible -i ansible-files/inventory all -m ping
# Expected: Should succeed if SSH works

# Test 5: Ansible-navigator (in EE with --network=host)
cd /home/rhel/ansible-files
ansible-navigator inventory --list
ansible-navigator run -m ping all --mode stdout
# Expected: Should succeed if Test 4 succeeded
```

---

### Phase 3: If DNS Still Fails, Check Subnet Assignment

```bash
# From control VM:
ip addr show eth0
# Note the IP (10.0.2.x or 10.130.x?)

# From each node (via SSH):
ssh rhel@node1 ip addr show eth0
ssh rhel@node2 ip addr show eth0
ssh rhel@node3 ip addr show eth0
# Note the IPs

# Check if all are on same subnet or mixed
```

If mixed subnets (control on 10.0.2.x, nodes on 10.130.x):
- This matches the reference lab topology
- DNS should still work (it does for the reference lab)
- If DNS fails, investigate CNV DNS configuration

If all on same subnet (all on 10.0.2.x):
- DNS failure would be surprising
- Check if dnsmasq or systemd-resolved is running
- Check /etc/resolv.conf

---

## Summary: What To Do

### Immediate Actions (High Confidence)

1. **Change node images from `devtools-ansible` to `rhel-9.6`**
   - Reference lab proves standard RHEL works
   - devtools-ansible adds unnecessary complexity for nodes
   - Faster provisioning, smaller images

2. **Remove HTTP services/routes from nodes**
   - Only control needs a service/route (for code-server)
   - Nodes only need SSH (provided by default)
   - Match reference lab's pattern

3. **Remove wait_for_connection timeout**
   - Let Ansible use default 600s
   - Match reference lab's approach

### Don't Do

1. ❌ **Don't add /etc/hosts configuration**
   - Reference lab doesn't use it
   - Previous attempt failed (commit aaaac02)
   - Adds complexity without proof it helps

2. ❌ **Don't change node naming convention**
   - Already consistent (node1/2/3 everywhere)
   - Not related to the problem

3. ❌ **Don't add network gathering plays**
   - Reference lab doesn't use them
   - Only needed if we were doing /etc/hosts (which we're not)

### Test After Changes

1. Provision lab in RHDP
2. Monitor showroom pod logs for setup-automation failures
3. SSH to control VM
4. Run DNS resolution tests (getent, ping, ssh)
5. Run ansible-navigator connectivity tests

---

## Files To Modify

### 1. config/instances.yaml

**Changes**:
- node1, node2, node3: Change `image: "devtools-ansible"` to `image: "rhel-9.6"`
- node1, node2, node3: Remove `services:` sections
- node1, node2, node3: Remove `routes:` sections
- Keep `userdata` (password auth configuration)

### 2. setup-automation/main.yml

**Changes**:
- Remove `timeout: 300` from wait_for_connection
- Remove `delay: 5` from wait_for_connection

### 3. No other files need changes

- setup-control.sh ✓ (correct as-is)
- setup-node*.sh ✓ (correct as-is)
- ansible-files/* ✓ (correct as-is)
- ui-config.yml ✓ (correct as-is)

---

## Expected Outcome

After these changes, the lab should:
1. Provision faster (smaller node images)
2. Have simpler network topology (only control has service/route)
3. Match reference lab's proven architecture
4. DNS resolution should work (node1/node2/node3 resolve to IPs)
5. ansible-navigator should connect to nodes successfully

If it still fails, the problem is deeper (CNV DNS issues, image-specific networking, etc.) and we'll need to investigate the actual provisioning logs and network state.
