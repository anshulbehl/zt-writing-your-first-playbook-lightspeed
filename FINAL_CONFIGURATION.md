# Final Lab Configuration Summary

## Network Architecture (All VMs on 10.0.2.x Subnet)

### Control Node
- **Name**: `control`
- **Image**: `devtools-ansible` (needs code-server for VS Code UI)
- **Service**: vscode-8080 (HTTP port 8080)
- **Route**: vscode-8080 → https://vscode-${guid}.${domain}/
- **Purpose**: Code-server web UI for students to edit playbooks

### Managed Nodes (node01, node02, node03)
- **Names**: `node01`, `node02`, `node03` (two-digit format)
- **Image**: `rhel-9.6` (standard RHEL, faster than devtools-ansible)
- **Services**: SSH port 22 for each node
- **Routes**: node01/02/03-ssh → enables wetty terminal access
- **Purpose**: Wetty tabs allow direct SSH to nodes via browser

## Why All Nodes Have Services/Routes

**Previously attempted**: Remove services from nodes → mixed subnets (control on 10.0.2.x, nodes on 10.130.x)
**Problem**: Wetty tabs require OpenShift routes, which require services defined

**Current solution**: All VMs have services/routes
- **Control**: HTTP:8080 (code-server)
- **Nodes**: SSH:22 (wetty access)

**Result**: All VMs land on 10.0.2.x subnet → same-subnet connectivity + wetty tabs work

## Key Changes from Original

### 1. Node Naming: node1/2/3 → node01/02/03
**Updated in**:
- instances.yaml VM names
- main.yml node loop
- All inventory files
- Runtime automation validations
- Setup script filenames
- ui-config.yml wetty tabs

### 2. Node Images: devtools-ansible → rhel-9.6
**Why**: Nodes don't need code-server or developer tools
**Benefit**: Faster provisioning, smaller image size

### 3. Node Services: HTTP:80 → SSH:22
**Why**: Nodes actually use SSH (not HTTP)
**Benefit**: Accurate configuration, enables wetty properly

### 4. Script Lookup: short_hostname → config_host
**Changed from**: `{{ inventory_hostname.split('.')[0] }}`
**Changed to**: `{{ ansible_host }}`
**Why**: Simpler, matches roadshow pattern

### 5. Wait Timeout: Removed
**Changed from**: `timeout: 300, delay: 5`
**Changed to**: (none - uses Ansible default 600s)
**Why**: Let Ansible handle timeouts naturally

## UI Tabs Configuration

```yaml
tabs:
  - name: VS Code
    url: https://vscode-${guid}.${domain}/
  - name: Control
    url: /wetty
  - name: Node01
    url: /wetty_node01
  - name: Node02
    url: /wetty_node02
  - name: Node03
    url: /wetty_node03
```

All wetty URLs use two-digit format matching VM names.

## Inventory Structure

```ini
[web]
node01
node02

[database]
node03

[nodes:children]
web
database

[all:vars]
ansible_user=rhel
ansible_connection=ssh
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
```

## Differences from Roadshow Lab

### What We Match
✅ Two-digit node naming (node01, node02, node03)
✅ Standard RHEL images for nodes
✅ Script lookup using ansible_host
✅ No wait timeout override
✅ Trust CNV DNS (no /etc/hosts)

### Intentional Differences
⚠️ **Control image**: devtools-ansible (we need code-server) vs aap-2.6-2-ceh (they need AAP)
⚠️ **Node services**: SSH:22 (for wetty) vs roadshow varies (node01 none, node02/03 HTTP:80)
⚠️ **Subnet strategy**: All on 10.0.2.x (same subnet) vs roadshow mixed subnets

### Why Different Subnet Strategy

**Roadshow can use mixed subnets** because:
- Their control node is AAP with special networking
- They don't have wetty tabs for nodes (commented out in ui-config.yml)
- Their students don't need browser-based node access

**We need same subnet** because:
- Wetty tabs require routes
- Routes require services
- Services → VMs land on 10.0.2.x
- Result: all VMs on same subnet

## Testing After Provision

### DNS Resolution (from control)
```bash
getent hosts node01 node02 node03
# Expected: IP addresses (10.0.2.x for each)
```

### Subnet Verification
```bash
# From control:
ip addr show eth0
# Expected: 10.0.2.x

# From each node (via SSH):
ssh rhel@node01 'ip addr show eth0'
# Expected: 10.0.2.x
```

### Ansible Connectivity
```bash
cd /home/rhel/ansible-files
ansible-navigator inventory --list
ansible-navigator run -m ping all --mode stdout
# Expected: All nodes respond
```

### Wetty Tabs
- Click Node01 tab → should open terminal to node01
- Click Node02 tab → should open terminal to node02
- Click Node03 tab → should open terminal to node03

## Files Modified

1. `config/instances.yaml` - VM definitions
2. `setup-automation/main.yml` - Node names, script lookup
3. `setup-automation/setup-control.sh` - Inventory node names
4. `setup-automation/setup-node{1,2,3}.sh` → renamed to `setup-node{01,02,03}.sh`
5. `ansible-files/inventory` - Node names
6. `runtime-automation/inventory` - Node names
7. `runtime-automation/01-playbook-inventory/validation.yml` - Node checks
8. `runtime-automation/01-playbook-inventory/solve.yml` - Inventory template
9. `ui-config.yml` - Wetty tab URLs

## Why This Should Work

1. **Same subnet** - All VMs on 10.0.2.x = direct connectivity
2. **Proper services** - SSH services match actual usage
3. **Standard images** - rhel-9.6 for nodes = faster provisioning
4. **Consistent naming** - node01/02/03 everywhere
5. **CNV DNS** - Handles hostname resolution naturally
6. **Wetty enabled** - Routes configured for browser terminal access
