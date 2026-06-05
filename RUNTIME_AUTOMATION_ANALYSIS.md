# Runtime Automation Analysis - What to Move to Setup

## Current Runtime Setup Scripts

| Module | Lines | Key Actions | Move to Setup? |
|--------|-------|-------------|----------------|
| 01 | 104 | **Heavy infrastructure setup** | ✅ **YES - ALL** |
| 02 | 24 | Debug messages only | ❌ No |
| 03 | 42 | Sample playbook + node packages | ⚠️ **Partial** |
| 04-10 | 16-18 | Debug messages only | ❌ No |

**Total lines:** 292 (104 can be moved to setup-automation)

---

## Module 01: Heavy Lifting (104 lines) - **MOVE ALL TO SETUP**

### Infrastructure Setup (Not Pedagogical)
These are one-time environment configuration - students don't learn from this:

**Control Node:**
```yaml
# Should be in setup-automation/setup-control.sh:
- Create AAP repo file (ansible-automation-platform.repo)
- Remove setup bundle tar.gz
- Disable subscription-manager warnings
- Create directories: /home/rhel/ansible-files, /home/rhel/.logs
- Create /home/rhel/.ansible.cfg
- Create /home/rhel/.gitconfig
- Create /home/rhel/.ansible-navigator.yml
- Copy ansible-navigator.yml to ansible-files/
```

**Nodes:**
```yaml
# Should be in setup-automation/setup-node*.sh:
- Disable subscription-manager warnings
```

### Why Move This?
- **Not learning content** - this is environment prep
- **Reduces first module latency** - 104 lines of Ansible execution → instant
- **Cleaner student experience** - environment is ready on arrival
- **Matches production pattern** - other labs do this in setup-automation

---

## Module 02: No Action Required
Just debug messages - exists to allow module progression without setup overhead.

---

## Module 03: Partial Move (42 lines)

### Can Move to Setup (36 lines):
```yaml
# On nodes - in setup-automation/setup-node*.sh:
- Install cups-filesystem package
- Disable SELinux (ansible.posix.selinux state: disabled)
```

### Should KEEP in Runtime (6 lines):
```yaml
# This is pedagogical - students see the playbook structure:
- Create system_setup.yml playbook template
```

**Why keep the playbook creation?**
- Module 03 is "Playbook Run It" - showing them a complete playbook is the lesson
- Creating it at runtime demonstrates the file structure students will use

---

## Modules 04-10: No Changes
All just debug messages - no setup to move.

---

## Recommended Changes to setup-automation/

### setup-control.sh (ADD ~80 lines):
```bash
#!/bin/bash
set -e

# ============================================
# Module 01 Infrastructure (from runtime-automation)
# ============================================

# Create AAP local repo
cat > /etc/yum.repos.d/ansible-automation-platform.repo << 'EOF'
[ansible-automation-platform]
name = Red Hat Ansible Automation Platform
baseurl = file:///var/ansible-automation-platform/el8_repos/
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

# Clean up setup bundle
rm -f /var/ansible-automation-platform-setup-bundle-2.4-6-x86_64.tar.gz

# Disable subscription-manager warnings
sed -i 's/^enabled.*$/enabled = 0/' /etc/yum/pluginconf.d/subscription-manager.conf

# Create user directories
mkdir -p /home/rhel/ansible-files
mkdir -p /home/rhel/.logs
chown -R rhel:rhel /home/rhel/ansible-files /home/rhel/.logs

# Create ansible.cfg
cat > /home/rhel/.ansible.cfg << 'EOF'
[defaults]
inventory = /home/rhel/ansible-files/inventory
host_key_checking = False
EOF
chown rhel:rhel /home/rhel/.ansible.cfg

# Create .gitconfig
cat > /home/rhel/.gitconfig << 'EOF'
[user]
  email = "rhel@example.com"
  name = Red Hat
EOF
chown rhel:rhel /home/rhel/.gitconfig

# Create ansible-navigator.yml
cat > /home/rhel/.ansible-navigator.yml << 'EOF'
---
ansible-navigator:
  ansible:
    inventory:
      entries:
      - /home/rhel/ansible-files/inventory
  execution-environment:
    container-engine: podman
    enabled: true
    image: quay.io/acme_corp/first_playbook_ee:latest
    pull:
      policy: missing
  logging:
    level: debug
    file: /home/rhel/.logs/ansible-navigator.log
  mode: stdout
  playbook-artifact:
    save-as: /home/rhel/.logs/{playbook_name}-artifact-{time_stamp}.json
EOF
chown rhel:rhel /home/rhel/.ansible-navigator.yml

# Copy to ansible-files directory
cp /home/rhel/.ansible-navigator.yml /home/rhel/ansible-files/ansible-navigator.yml
chown rhel:rhel /home/rhel/ansible-files/ansible-navigator.yml

echo "Control node setup complete"
```

### setup-node{1,2,3}.sh (ADD ~10 lines each):
```bash
#!/bin/bash
set -e

# ============================================
# Module 01 & 03 Infrastructure
# ============================================

# Disable subscription-manager warnings
sed -i 's/^enabled.*$/enabled = 0/' /etc/yum/pluginconf.d/subscription-manager.conf

# Install packages needed for module 03
dnf install -y cups-filesystem

# Disable SELinux for exercises
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

echo "Node setup complete"
```

---

## Impact Analysis

### Time Savings
| Module | Current Setup Time | After Move | Saved |
|--------|-------------------|------------|-------|
| 01 | ~30-45s (Ansible execution) | ~1s (instant) | 29-44s |
| 03 | ~15-20s (package install) | ~1s (instant) | 14-19s |
| **Total** | **45-65s** | **2s** | **43-63s** |

### Provision Time Impact
- Current setup-automation: ~60-90s
- After changes: ~120-150s (adds ~60s for packages/config)
- **Trade:** 60s more upfront, 43-63s saved during lab = net neutral, better UX

### Student Experience
**Before:**
- Module 01: Wait 30-45s for environment setup (confusing - "why am I waiting?")
- Module 03: Wait 15-20s for package install

**After:**
- Module 01: Instant (environment pre-configured)
- Module 03: Instant (packages pre-installed)
- **Result:** Smoother flow, less confusion

---

## Runtime Automation After Changes

### Module 01 setup.yml (REDUCED TO ~8 LINES):
```yaml
---
- name: Setup control node
  hosts: controller
  gather_facts: false
  tasks:
    - name: Verify environment
      ansible.builtin.debug:
        msg: "Environment ready"

- name: Setup nodes
  hosts: nodes
  gather_facts: false
  tasks:
    - name: Verify environment
      ansible.builtin.debug:
        msg: "Environment ready"
```

### Module 03 setup.yml (REDUCED TO ~20 LINES):
```yaml
---
- name: Create sample playbook
  hosts: controller
  vars:
    USER: rhel
  tasks:
    - name: Create system-setup.yml
      ansible.builtin.copy:
        content: |
          ---
          - name: Basic System Setup
            hosts: node1
            become: true
            tasks:
              - name: Install security updates for the kernel
                ansible.builtin.dnf:
                  name: 'kernel'
                  state: latest
                  security: true

              - name: Create a new user
                ansible.builtin.user:
                  name: myuser
                  state: present
                  create_home: true
        dest: /home/{{ USER }}/ansible-files/system_setup.yml
        owner: "{{ USER }}"
        group: "{{ USER }}"
        mode: "0644"
```

---

## Recommendation: **IMPLEMENT**

**Reasons:**
1. ✅ **Faster module progression** - no setup lag
2. ✅ **Clearer pedagogical focus** - runtime scripts only do lesson-specific tasks
3. ✅ **Matches production patterns** - other ANS BU labs do this
4. ✅ **Better student experience** - environment "just works"
5. ✅ **Minimal tradeoff** - 60s more provision time is acceptable

**Caveats:**
- ⚠️ Need to test AAP repo file path exists on rhel-9.6 image
- ⚠️ Verify `/var/ansible-automation-platform-setup-bundle-2.4-6-x86_64.tar.gz` exists on image
- ⚠️ Verify `quay.io/acme_corp/first_playbook_ee:latest` image is accessible

**Alternative if image not ready:**
- Keep AAP repo setup in runtime (module 01)
- Still move: directories, configs, gitconfig, node packages (saves ~25s)

---

**Summary:** Move 104 lines from runtime to setup = **instant module start**, better UX, matches prod patterns.
