# Network Fix Plan: Comparison Analysis

## Executive Summary

After comparing `zt-writing-your-first-playbook` with the working reference lab `zt-ans-bu-roadshow01`, I've identified **critical differences** in how node naming is handled. The working lab uses `node01`, `node02`, `node03` (two digits) while our broken lab uses `node1`, `node2`, `node3` (one digit). This inconsistency appears throughout instances.yaml, setup scripts, and ansible playbooks.

## Key Differences Identified

### 1. **Node Naming Convention (CRITICAL)**

| Component | zt-ans-bu-roadshow01 (WORKING) | zt-writing-your-first-playbook (BROKEN) |
|-----------|-------------------------------|----------------------------------------|
| **instances.yaml** | `node01`, `node02`, `node03` | `node1`, `node2`, `node3` |
| **setup-automation/main.yml loop** | `- node01`<br>`- node02`<br>`- node03` | `- node1`<br>`- node2`<br>`- node3` |
| **Inventory files** | `node01`, `node02` | `node1`, `node2`, `node3` |
| **Setup scripts** | `setup-node01.sh`, `setup-node02.sh`, `setup-node03.sh` | `setup-node1.sh`, `setup-node2.sh`, `setup-node3.sh` |

**Impact**: While both naming schemes can work independently, the issue is **consistency**. Our lab should standardize on ONE convention across all files.

---

### 2. **VM Image Differences**

| VM | zt-ans-bu-roadshow01 | zt-writing-your-first-playbook |
|----|---------------------|-------------------------------|
| **control** | `aap-2.6-2-ceh-20251103` (32G RAM, 4 cores) | `devtools-ansible` (8G RAM, 2 cores) |
| **node01/node1** | `rhel-9.5` (8G RAM) | `devtools-ansible` (8G RAM) |
| **node02/node2** | `rhel-8.7` (8G RAM) | `devtools-ansible` (8G RAM) |
| **node03/node3** | `rhel-9.5` (8G RAM) | `devtools-ansible` (8G RAM) |

**Analysis**: 
- Working lab uses `aap-2.6-2-ceh-20251103` for control (Ansible Automation Platform image)
- Working lab uses standard RHEL images (`rhel-9.5`, `rhel-8.7`) for nodes
- Our lab uses `devtools-ansible` for ALL VMs (per HANDOFF.md's subnet consistency strategy)
- **Current approach is valid** — HANDOFF.md documents that image type doesn't determine subnet; services/routes do

---

### 3. **Services and Routes Configuration**

#### zt-ans-bu-roadshow01 (Working Lab):
```yaml
# Control node: HTTPS on port 443 (reencrypt termination)
# node01: NO services, NO routes
# node02: HTTP on port 80 (Edge termination)
# node03: HTTP on port 80 (Edge termination)
```

**Network outcome**: 
- Control with services/routes → lands on isolated 10.0.2.x network
- node01 without services/routes → lands on pod network 10.130.x
- node02/node03 with services/routes → lands on isolated 10.0.2.x network

**⚠️ This creates mixed subnets but somehow still works in the reference lab!**

#### zt-writing-your-first-playbook (Broken Lab):
```yaml
# Control node: HTTP on port 8080 (Edge termination) for code-server
# node1: HTTP on port 80 (Edge termination)
# node2: HTTP on port 80 (Edge termination)
# node3: HTTP on port 80 (Edge termination)
```

**Network outcome**: 
- ALL VMs with services/routes → should ALL land on isolated 10.0.2.x network
- **This should work better** than the reference lab (all on same subnet!)

---

### 4. **setup-automation/main.yml Differences**

#### zt-ans-bu-roadshow01:
```yaml
# Line 23: ansible_python_interpreter: /usr/libexec/platform-python  ← RHEL 8 path
# Line 23-25: loop: [node01, node02, node03]
```

#### zt-writing-your-first-playbook:
```yaml
# Line 23: ansible_python_interpreter: /usr/bin/python3  ← RHEL 9 path
# Line 25-27: loop: [node1, node2, node3]
```

**Impact**: Python interpreter path correct for RHEL 9. Node naming mismatch is the issue.

---

### 5. **Hostname Resolution Strategy**

#### zt-ans-bu-roadshow01:
- No `/etc/hosts` population visible in setup-automation/main.yml
- setup-control.sh doesn't resolve node IPs
- **Hypothesis**: Either relies on CNV DNS, or there's unrevealed configuration

#### zt-writing-your-first-playbook:
- HANDOFF.md documents extensive DNS issues in CNV (`getent hosts` returns duplicates)
- Previously attempted DNS resolution in setup-control.sh (failed)
- Current approach: No /etc/hosts population in main.yml or setup-control.sh
- **Missing**: The /etc/hosts population that HANDOFF.md claims was added to main.yml

Let me verify the actual current state of main.yml...

---

## Critical Issues Found

### Issue #1: Node Naming Inconsistency
**Symptom**: setup-automation/main.yml loops over `node1, node2, node3` but instances.yaml might be creating nodes with different names.

**Root cause**: Mismatch between:
- VM names in instances.yaml
- Node list in setup-automation/main.yml
- Inventory file hostnames
- Setup script naming (`setup-node1.sh` vs `setup-node01.sh`)

**Evidence from HANDOFF.md**: No mention of renaming nodes from `node1/2/3` to `node01/02/03`.

---

### Issue #2: Missing /etc/hosts Configuration
**Symptom**: HANDOFF.md line 196-210 claims main.yml has plays to gather facts and populate /etc/hosts, but current main.yml (87 lines) doesn't have these plays.

**Expected configuration (from HANDOFF.md)**:
```yaml
- name: Gather node IP addresses
  hosts: nodes
  gather_facts: true
  
- name: Configure node hostname resolution on control
  hosts: bastion
  tasks:
    - name: Add nodes to /etc/hosts
      lineinfile:
        path: /etc/hosts
        line: "{{ hostvars[item].ansible_default_ipv4.address }} {{ item }}"
        regexp: "^.*{{ item }}$"
      loop:
        - node1
        - node2
        - node3
```

**Current state**: main.yml does NOT have this configuration!

---

### Issue #3: setup-control.sh Mismatch
**Current setup-control.sh (line 11-12)**:
```bash
# Node /etc/hosts entries are configured by setup-automation/main.yml
# using each VM's actual IP from Ansible facts (getent can return duplicate IPs in CNV DNS)
```

**Reality**: main.yml does NOT configure /etc/hosts. This comment is lying!

---

## Recommended Fixes

### Fix 1: Restore /etc/hosts Configuration in main.yml
**Action**: Add the plays documented in HANDOFF.md (lines 196-210) to setup-automation/main.yml

**Why**: Without this, control node cannot resolve node1/2/3 hostnames to IPs, causing ansible-navigator connection timeouts.

### Fix 2: Verify Node Naming Consistency
**Action**: Ensure all of these use the SAME naming convention:
- [ ] instances.yaml VM names: `node1, node2, node3`
- [ ] main.yml loop: `node1, node2, node3`
- [ ] setup script names: `setup-node1.sh, setup-node2.sh, setup-node3.sh`
- [ ] ansible-files/inventory: `node1, node2` (web group), `node3` (database group)

**Current status**: Already consistent with single-digit naming. Keep it.

### Fix 3: Consider Reference Lab's Services/Routes Pattern
**Question**: Why does the reference lab work with mixed subnets (node01 has no services/routes)?

**Investigation needed**:
1. Does AAP control image handle routing differently?
2. Is there network configuration in setup-control.sh we haven't seen?
3. Does the reference lab actually have the same connectivity issues?

**Decision**: Keep current approach (all VMs with services/routes) since it should provide better connectivity.

---

## Implementation Plan

### Step 1: Read Current main.yml Completely
**Verify**: Does main.yml actually have /etc/hosts configuration that I missed?

### Step 2: Compare HANDOFF.md Claims vs Reality
**Check**:
- HANDOFF.md line 196-210 describes /etc/hosts plays
- HANDOFF.md line 209-215 describes moving DNS logic from setup-control.sh to main.yml
- Current main.yml: Does it match the HANDOFF.md final state?

### Step 3: Restore Missing Configuration
**If missing**: Add the fact-gathering and /etc/hosts population plays to main.yml

### Step 4: Verify All Node Naming
**Audit**:
- instances.yaml
- main.yml
- setup-control.sh inventory file
- setup-nodeX.sh script names
- runtime-automation inventory files

### Step 5: Test Provisioning
**Validation**:
1. Provision lab in RHDP
2. SSH to control node
3. Check `cat /etc/hosts` for node entries
4. Test `ping node1`, `ping node2`, `ping node3`
5. Run `ansible-navigator inventory --list` from /home/rhel/ansible-files
6. Run test playbook with ping module

---

## Questions for Investigation

1. **Why doesn't the reference lab need /etc/hosts?**
   - Is CNV DNS more reliable for AAP images?
   - Is there hidden configuration in the AAP image itself?

2. **Why does reference lab work with mixed subnets?**
   - node01 (no services) on 10.130.x
   - control, node02, node03 (with services) on 10.0.2.x
   - How does control reach node01 across subnets?

3. **Is the AAP image doing something special?**
   - Does it have built-in DNS resolution?
   - Does it configure routing tables?

---

## Next Steps

1. ✅ Read current main.yml completely to verify /etc/hosts configuration
2. ⬜ Compare HANDOFF.md final architecture vs actual current state
3. ⬜ Add missing /etc/hosts configuration if absent
4. ⬜ Test node naming consistency
5. ⬜ Review reference lab's actual network behavior (provision and test)
