# AWS to CNV Conversion - Final Status

## Conversion Complete ✅

Successfully converted "Writing Your First Playbook" lab from AWS EC2 to OpenShift CNV using the **composite catalog item pattern**.

## Files Created/Modified

### Showroom Repository (`zt-writing-your-first-playbook/`)

**Created:**
```
config/
├── instances.yaml       # 5 VMs (control: 8G, nodes: 8G each, vscode: 8G)
├── firewall.yaml        # Egress/ingress rules for HTTP/HTTPS/SSH
└── networks.yaml        # Default pod network

setup-automation/
├── main.yml             # Ansible playbook (inventory + script execution)
├── ansible.cfg          # Basic Ansible config
├── setup-control.sh     # Creates ansible-files directory + ansible.cfg
├── setup-vscode.sh      # VSCode workspace configuration
└── setup-node{1,2,3}.sh # Minimal setup (SSH via cloud-init)

ui-config.yml            # ROOT - modern URL format with ${guid}/${domain}
CONVERSION_SUMMARY.md
FINAL_STATUS.md
```

**Preserved:**
```
zero-touch-config.yml    # Original AWS UI config (for AWS catalog item)
runtime-automation/      # Solve button automation (works for both)
```

### Catalog Repository (`zt-ans-bu-writing-playbook-cnv/`)

**Created:**
```
common.yaml              # 43 lines - composite pattern
dev.yaml                 # Cloud selector: cnv + lifetime-standard
test.yaml
prod.yaml
event.yaml               # Cloud selector: cnv + lifetime-event
description.adoc         # Catalog display text
```

## VM Configuration

| VM | Image | RAM | Cores | Disk | Purpose |
|----|-------|-----|-------|------|---------|
| control | rhel-9.6 | 8G | 2 | 30Gi | Control node for Ansible |
| node1-3 | rhel-9.6 | 8G | 2 | 30Gi | Managed nodes |
| vscode | devtools-ansible | 8G | 2 | 20Gi | VSCode web editor |

**Notes:**
- All VMs: 8G RAM (increased from initial 2G/4G for better performance)
- VSCode VM requires: `disk_type: scsi`, `bootloader: efi`
- All use cloud-init for user setup: `rhel/ansible123!`

## Network Configuration

**firewall.yaml (NetworkPolicy):**
- **Egress:** 443, 80, 22 (HTTPS, HTTP, SSH to external)
- **Ingress:** 443, 8080, 80, 22 (HTTPS, VSCode, HTTP, SSH)

**Platform defaults (always present):**
- Ingress: 80, 443, 8080 from internet
- Ingress: 22 (SSH) from showroom pod only
- Egress: DNS (5353), VM-to-VM SSH (22)
- Egress: 443 is BLOCKED by default - we explicitly allow it

**networks.yaml:**
- Single network: `default` (pod network)
- Internal communication: automatic via pod DNS
- Hostnames: control, node1, node2, node3, vscode

## UI Configuration

**ui-config.yml (root):**
```yaml
tabs:
  - name: VS Code
    url: https://vscode-${guid}.${domain}/
    external: false
  - name: Control
    url: /wetty
    external: false
```

**Tab access:**
- VS Code: Route to vscode VM port 8080 (code-server preinstalled)
- Control: Wetty SSH bastion (provided by base component)

**Modules:** 10 interactive modules with solve buttons (01-10)

## Catalog Item Pattern

**Composite (43 lines):**
```yaml
__meta__:
  deployer:
    type: null  # Composite marker
  components:
  - name: zt-lab-developer-cnv
    item: zt-ansiblebu/zt-ans-bu-lab-developer-cnv
    parameter_values:
      ocp4_workload_showroom_content_git_repo: https://github.com/redhat-gpte-devopsautomation/zt-writing-your-first-playbook.git
      ocp4_workload_showroom_namespace_wait_ready: 1200
      ocp4_workload_showroom_ironrdp_enable: false
```

**Inherits from base:**
- CNV cloud provider configuration
- Showroom Helm chart deployment (zerotouch v1.10.2)
- Wetty SSH bastion
- Setup automation execution
- User credentials from ansiblebu_rhel_password secret

**Overrides:**
- Git repo URL
- Timeout (1200s = 20 minutes)
- Disables IronRDP (not needed for this lab)

## Setup Automation

**Lifecycle:**
1. Git-cloner (init) → clones showroom repo
2. Antora-builder (init) → builds documentation
3. **Setup (init)** → runs `setup-automation/main.yml`
4. Main containers start

**setup-automation/main.yml:**
- Creates dynamic inventory from BASTION_* env vars
- Adds all 5 VMs to inventory
- Waits for SSH (22) to be open
- Copies setup-*.sh to each VM
- Executes as root via `become: true`
- Captures output, fails on error

**Setup scripts:**
- `setup-control.sh`: Creates `/home/rhel/ansible-files/`, ansible.cfg
- `setup-vscode.sh`: Configures code-server workspace
- `setup-node{1,2,3}.sh`: Minimal (SSH already via cloud-init)

## Cloud Selector

**Targets:** Legacy CNV clusters
```yaml
cloud_selector:
  cloud: cnv
  purpose: prod
  virt: "yes"
```

**Matches:** `ocpv05`, `ocpv08`, `ocpv10` (bare-metal CNV prod)

**Does NOT match:** HCP clusters (`cnv-us-east-ocp-*`) - need `cloud: cnv-shared`

## Image Requirements

| Image | Availability | Action Required |
|-------|-------------|-----------------|
| rhel-9.6 | ✅ Standard | Should exist in all CNV clusters |
| devtools-ansible | ⚠️ **VERIFY** | Confirm PVC exists or request via PTMP team |

**devtools-ansible details:**
- Prebuilt image with code-server on port 8080
- Requires SCSI disk type and EFI bootloader
- Alternative: Install code-server in setup-control.sh (slower)

## Testing Checklist

**Pre-deployment:**
- [ ] Verify `rhel-9.6` PVC in `cnv-images` namespace
- [ ] **Verify `devtools-ansible` PVC** (critical - request if missing)
- [ ] Push showroom changes to GitHub
- [ ] Run `agnosticv --merge` + `babylon_checks.py`

**Post-deployment (dev):**
- [ ] All 5 VMs in Running state
- [ ] Setup automation completes (check pod logs: `oc logs <pod> -c setup`)
- [ ] VS Code tab loads (https://vscode-<guid>.<domain>/)
- [ ] Control tab connects (wetty terminal)
- [ ] SSH connectivity: `ssh node1` from control VM
- [ ] Ansible inventory works: `ansible -i /home/rhel/ansible-files/inventory all -m ping`
- [ ] Solve button works (module 01)
- [ ] No NetworkPolicy blocks (check egress 443/80 work)

## Known Issues / Considerations

1. **devtools-ansible image availability:** Must verify before deploying. If missing:
   - Option A: Request from PTMP team (manual upload pipeline)
   - Option B: Modify to install code-server in setup-control.sh

2. **Timeout tuning:** 1200s should be sufficient for 5 VMs + setup
   - If setup is complex, increase to 1800s or 2700s

3. **Memory allocation:** All VMs at 8G (increased from original)
   - Control: 8G (originally 4G) for Ansible operations
   - Nodes: 8G each (originally 2G) for lab exercises
   - VSCode: 8G (standard for devtools image)

4. **Runtime automation unchanged:** Solve buttons reference control/node1-3 hostnames
   - Inventory in runtime scripts must match instances.yaml names
   - SSH key: `/app/.ssh/labkey.pem` (Babylon provisioning key)

## Comparison: AWS vs CNV

| Aspect | AWS (EC2) | CNV (OpenShift) |
|--------|-----------|-----------------|
| **Pattern** | Standalone catalog (227 lines) | Composite (43 lines) |
| **Infra** | 4 EC2 instances | 5 CNV VMs in namespace |
| **Images** | AMI (zt-control/node-19-july-2024) | PVC clone (rhel-9.6, devtools-ansible) |
| **VSCode** | nginx on control + vscode-server role | Separate VM with prebuilt image |
| **Terminal** | Showroom SSH to host.containers.internal | Wetty SSH bastion |
| **UI config** | `port/path` (deprecated) | `url` with ${guid}/${domain} |
| **Setup** | AgnosticD roles (vscode-server, showroom) | setup-automation playbook + scripts |
| **Network** | Security groups, floating IPs | NetworkPolicy, OCP routes |
| **Provision time** | ~10-15 min | ~15-20 min (includes VM cloning) |

## Next Steps

1. **Verify devtools-ansible image:**
   ```bash
   oc get pvc -n cnv-images | grep devtools-ansible
   ```

2. **Push showroom changes:**
   ```bash
   cd ~/Projects/showrooms_all/zt-writing-your-first-playbook/
   git add .
   git commit -m "Add CNV support with composite pattern"
   git push origin main
   ```

3. **Validate catalog item:**
   ```bash
   cd ~/Projects/agnosticv_all/zt-ansiblebu-agnosticv/
   agnosticv --merge
   python3 babylon_checks.py
   ```

4. **Deploy to dev sandbox:**
   - Use Babylon UI
   - Select: zt-ans-bu-writing-playbook-cnv
   - Environment: dev
   - Monitor logs: `oc get pods -n <namespace>` and `oc logs <pod> -c setup`

5. **Test full workflow:**
   - Access tabs, run playbooks, verify networking

---

**Conversion Date:** 2026-06-05  
**Pattern:** Ansible BU composite (inherits from zt-ans-bu-lab-developer-cnv)  
**Status:** ✅ Ready for testing (verify devtools-ansible image first)  
**Total VMs:** 5 (control + node1-3 + vscode)  
**Total RAM:** 40G (8G × 5)  
**Timeout:** 1200s (20 minutes)
