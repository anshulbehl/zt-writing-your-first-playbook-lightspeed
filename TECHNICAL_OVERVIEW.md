# Technical Overview: zt-writing-your-first-playbook

## What This Lab Is

A zero-touch RHDP lab where students learn to write Ansible playbooks using Ansible Lightspeed (AI code generation in VS Code). Students edit playbooks in a browser-based VS Code, then run them from a terminal — both on the same control VM.

**Platform**: AgnosticV/Babylon on OpenShift CNV (KubeVirt)
**Base config**: `zero-touch-base-rhel`
**Content delivery**: Showroom (Antora AsciiDoc)

---

## Infrastructure

### VMs (defined in `config/instances.yaml`)

| VM | Image | Purpose | Services/Routes |
|---|---|---|---|
| `control` | `devtools-ansible` | VS Code (code-server:8080) + ansible-navigator terminal | vscode-8080 (TCP 8080) |
| `node1` | `rhel-9.6` | Managed node (web group) | node1-ssh (TCP 22) |
| `node2` | `rhel-9.6` | Managed node (web group) | node2-ssh (TCP 22) |
| `node3` | `rhel-9.6` | Managed node (database group) | node3-ssh (TCP 22) |

All VMs get cloud-init userdata that sets user `rhel` with password `ansible123!` and enables password authentication in sshd.

**Critical**: The `devtools-ansible` image has a broken libcrypto — `ssh-keygen` produces keys that fail with "error in libcrypto" for both ed25519 and RSA. No `expect` or `sshpass` is available either. SSH key generation must happen elsewhere (see Setup Automation below).

### Networking

**KubeVirt masquerade networking**: Every VM sees itself as `10.0.2.2` behind its own pod's NAT. VMs communicate via Kubernetes pod IPs, not VM-internal IPs.

- `config/networks.yaml` — single `default` pod network
- `config/firewall.yaml` — generates Kubernetes NetworkPolicy rules:
  - **Egress**: TCP 443, 80, 22 + UDP/TCP 53 (DNS)
  - **Ingress**: TCP 8080 (code-server), TCP 22 (SSH)
  - The explicit egress list **replaces** platform defaults. If SSH (22) or DNS (53) are missing, VMs can't reach each other or resolve hostnames.

**Important networking facts**:
- Ping does NOT work under masquerade (ICMP not forwarded to guest). Use `nc -vz <host> 22` to test connectivity.
- There is no `firewalld` on the rhel-9.6 nodes (command not found). All firewall rules are at the Kubernetes NetworkPolicy layer.
- DNS resolution in CNV can return duplicate/stale IPs via `getent hosts`. Ansible facts (`ansible_default_ipv4.address`) are more reliable.

### Student-Facing Tabs (defined in `ui-config.yml`)

| Tab | URL | Target |
|---|---|---|
| VS Code | `https://vscode-${guid}.${domain}/` | code-server on control:8080 |
| Control | `/wetty` | SSH terminal to control VM |
| Node1 | `/wetty_node1` | SSH terminal to node1 |
| Node2 | `/wetty_node2` | SSH terminal to node2 |
| Node3 | `/wetty_node3` | SSH terminal to node3 |

---

## Setup Automation

Setup runs from the **showroom pod** (not from any VM). The showroom pod has special network access to all VMs and a working OpenSSL/ssh-keygen.

### `setup-automation/main.yml` — orchestrator

Runs in order:

1. **Play 1: Create inventory** — builds dynamic Ansible inventory from environment variables (`BASTION_HOST`, `BASTION_PORT`, `BASTION_USER`, `BASTION_PASSWORD` for control; same port/user/pass for nodes). These env vars are injected by the RHDP platform.

2. **Play 2: Setup VMs** — runs on `all:!localhost`:
   - Waits for SSH connectivity (`wait_for_connection`)
   - Copies `setup-<hostname>.sh` to each VM
   - Executes the script with `become: true`, passing `SATELLITE_URL`, `SATELLITE_ORG`, `SATELLITE_ACTIVATIONKEY` as env vars
   - Fails the entire play if any script exits non-zero

3. **Play 3: Generate SSH keypair** — runs on `localhost` (showroom pod):
   - `ssh-keygen -t rsa -b 4096` to `/tmp/lab-ssh-key`
   - Uses `creates:` to be idempotent

4. **Play 4: Distribute SSH keys** — runs on `all:!localhost`:
   - Copies private key (`id_rsa`) + public key (`id_rsa.pub`) to control VM
   - Writes public key to `authorized_keys` on node1, node2, node3
   - Uses `inventory_hostname == bastion_host` to distinguish control from nodes

### `setup-automation/setup-control.sh`

Runs on the control VM (devtools-ansible image). No `set -e` (diagnostic commands can fail without killing the script).

What it does:
1. Writes network diagnostics to `/home/rhel/network-debug.txt` (IP, routes, DNS resolution, gateway ping)
2. Creates SSH config for rhel user (`StrictHostKeyChecking no` for node1/node2/node3)
3. Creates `/home/rhel/ansible-files/` with:
   - `ansible.cfg` — points to inventory, disables host key checking
   - `ansible-navigator.yml` — configures execution environment (`quay.io/acme_corp/first_playbook_ee:latest`), `--network=host` container option, stdout mode
   - `inventory` — web group (node1, node2), database group (node3), `ansible_user=rhel`, `ansible_password=ansible123!`
   - `templates/motd.j2` — Jinja2 template for MOTD exercise
4. Configures and starts code-server (VS Code in browser) on port 8080

**Note**: `ansible-navigator` runs playbooks inside a container (execution environment). The `--network=host` option is critical — it lets the EE container use the control VM's `/etc/hosts` and network stack to reach nodes.

### `setup-automation/setup-node{1,2,3}.sh`

All three are identical in structure. No `set -e`. Register with Red Hat Satellite so students can install packages (httpd, etc.):

1. Download and trust Satellite CA cert
2. Install katello-ca-consumer RPM (if not present)
3. Register with subscription-manager using org + activation key
4. Each step has a `retry()` wrapper (3 attempts with 5s backoff)

The `grep -c katello || true` pattern prevents the grep exit code (1 = no match) from killing the script.

---

## Runtime Automation

Runs when students click "Solve" or "Check" buttons in the Showroom UI.

### `runtime-automation/main.yml` — dispatcher

Takes `module_dir` and `module_stage` as extra vars, runs the corresponding playbook (e.g., `01-playbook-inventory/solve.yml`). Uses a separate inventory (`runtime-automation/inventory`) that maps `controller` → control, `web` → node1/node2, `database` → node3.

### Module structure

Each module directory (`01-playbook-inventory/`, `02-generate-comprehensive-playbook/`, `03-playbook-run-it/`, `04-wrap-up/`) contains:
- `solve.yml` — auto-completes the exercise for the student
- `validation.yml` — checks if the student did it correctly

**Module 01** (Meet Ansible Lightspeed): Validates inventory file exists with correct groups and node assignments.

**Module 02** (Generate a Comprehensive Playbook): Solve creates `system_setup.yml` with apache/user/template tasks. No firewalld (not available on nodes).

**Module 03** (Run and Verify): Solve runs the playbook. Validation checks httpd is installed and running on web group, user exists on all nodes, MOTD template deployed.

**Module 04** (Wrap-Up): Informational only, no solve/validation.

---

## Content (Showroom AsciiDoc)

Located in `content/modules/ROOT/pages/`. Four modules corresponding to the runtime automation structure above.

- `site.yml` — Antora config, start page is `01-playbook-inventory.adoc`, uses nookbag-bundle UI
- `content/antora.yml` — component descriptor (no `nav:` section — zero-touch labs use `ui-config.yml` for navigation)
- Images in `content/modules/ROOT/assets/images/`

AsciiDoc nested collapsible blocks require different delimiter lengths (`=====` outer, `====` inner, `===` innermost) — AsciiDoc treats same-length delimiters as closing the outer block.

---

## Key Files Reference

```
config/
  instances.yaml          # VM definitions (4 VMs)
  networks.yaml           # Single default network
  firewall.yaml           # Kubernetes NetworkPolicy rules

setup-automation/
  main.yml                # Orchestrator: inventory → setup scripts → SSH keys
  setup-control.sh        # Control VM: diagnostics, SSH config, ansible-files, code-server
  setup-node1.sh          # Node1: Satellite registration
  setup-node2.sh          # Node2: Satellite registration
  setup-node3.sh          # Node3: Satellite registration

runtime-automation/
  main.yml                # Dispatcher for solve/validation
  inventory               # Maps controller/web/database to VMs
  01-playbook-inventory/  # Module 1 solve + validation
  02-generate-comprehensive-playbook/
  03-playbook-run-it/
  04-wrap-up/

ansible-files/            # Reference copies of student workspace files
  inventory
  ansible.cfg
  ansible-navigator.yml
  templates/motd.j2

content/                  # Showroom AsciiDoc content
  antora.yml
  modules/ROOT/pages/     # 4 module pages
  modules/ROOT/assets/    # Screenshots

ui-config.yml             # Showroom tabs + module solve buttons
site.yml                  # Antora site config
```

---

## Environment Variables (injected by RHDP platform)

| Variable | Used by | Purpose |
|---|---|---|
| `BASTION_HOST` | main.yml | Hostname/route for control VM |
| `BASTION_PORT` | main.yml | SSH port for all VMs |
| `BASTION_USER` | main.yml | SSH user (rhel) |
| `BASTION_PASSWORD` | main.yml | SSH password for setup |
| `SATELLITE_URL` | setup-node*.sh | Satellite server for package repos |
| `SATELLITE_ORG` | setup-node*.sh | Satellite org for registration |
| `SATELLITE_ACTIVATIONKEY` | setup-node*.sh | Satellite activation key |
| `guid` | ui-config.yml | Lab instance GUID (used in URLs) |
| `domain` | ui-config.yml | Cluster domain (used in URLs) |

---

## Ansible Lightspeed / LiteMaaS Integration

The Ansible VS Code extension's Lightspeed features (playbook generation, Explain) are backed by a **LiteMaaS** endpoint — Red Hat AI's Model-as-a-Service platform built on LiteLLM. LiteMaaS provides OpenAI-compatible `/v1/chat/completions` endpoints.

### How it works

1. The LiteMaaS base URL (`https://maas-rhdp.apps.maas.redhatworkshops.io`) and model (`openai/deepseek-r1-distill-qwen-14b`) are hardcoded in `setup-control.sh`
2. The API key is stored in `config/secrets.yaml`, encrypted with Ansible Vault (vault ID: `ansiblebu_vault`)
3. `setup-automation/main.yml` loads the secrets via `include_vars` and passes the key to `setup-control.sh`. It also copies the bundled extension vsix to the control VM.
4. `setup-control.sh` writes VS Code `settings.json` files (user-level and workspace-level) with:
   - `ansible.lightspeed.enabled: true`
   - `ansible.lightspeed.provider: "rhcustom"` — selects the Red Hat AI (OpenAI-compatible) provider
   - `ansible.lightspeed.apiEndpoint` — the LiteMaaS base URL
   - `ansible.lightspeed.apiKey` — the pre-provisioned API key
   - `ansible.lightspeed.modelName` — the model name
5. `setup-control.sh` installs the bundled Ansible extension v26.6.0 (`setup-automation/ansible-26.6.0.vsix`) via `code-server --install-extension` before starting code-server
6. On first activation, the extension auto-migrates these into its internal storage (globalState + secrets) and scrubs the API key from settings.json

### Why bundle the extension vsix

The `rhcustom` provider was added in v26.3.4, but settings.json migration support for `rhcustom` was only added in **v26.6.0**. The devtools-ansible image ships an older version without this support. The vsix (9.7MB) is bundled at `setup-automation/ansible-26.6.0.vsix` to avoid network downloads during provisioning.

### Known issue: auth redirect

The extension may still prompt a Red Hat SSO login redirect even with `rhcustom` configured. This appears to be a higher-level auth gate in the extension that fires regardless of provider type. The redirect fails with "Mismatching redirect URI" because code-server's callback URL isn't registered in Red Hat SSO. **This is an open issue being investigated.**

### Graceful degradation

If `LITEMAAS_API_KEY` is empty (e.g. vault decryption fails or secrets not loaded), the setup script skips Lightspeed configuration and logs a warning. The lab content and exercises still work — students just won't get AI-generated suggestions.

### Vault setup

The API key in `config/secrets.yaml` is encrypted with vault ID `ansiblebu_vault` — the standard vault ID for RHDP Ansible BU labs. The RHDP platform provides this vault password automatically at runtime.

---

## Known Constraints and Gotchas

1. **devtools-ansible libcrypto is broken** — cannot generate or use SSH keys on the control VM. Keys must be generated on the showroom pod and copied over.

2. **No firewalld on rhel-9.6 nodes** — any playbook tasks managing firewalld will fail with "Could not find the requested service firewalld." All firewall control is at the Kubernetes NetworkPolicy layer via `config/firewall.yaml`.

3. **cloud-init works on rhel-9.6 nodes but NOT on devtools-ansible** — the control VM's userdata may not be applied. code-server config and file setup is handled by `setup-control.sh` instead.

4. **Explicit egress in firewall.yaml replaces platform defaults** — if you add an egress section, you must include ALL needed ports (SSH 22, DNS 53, HTTP 80, HTTPS 443). Missing any one of these breaks connectivity.

5. **Ping is not a valid connectivity test** — masquerade networking doesn't forward ICMP. Use `nc -vz <host> 22` instead.

6. **ansible-navigator EE needs `--network=host`** — without it, the execution environment container can't reach nodes because it has its own network namespace.

7. **`set -e` in setup scripts is dangerous** — diagnostic commands (ip addr, grep, ping) return non-zero on benign conditions. The node scripts use `|| true` guards instead. setup-control.sh has no `set -e`.

8. **Satellite registration retry pattern** — `grep -c katello` returns exit code 1 when count is zero. Must use `|| true` to prevent script death.
