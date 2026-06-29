# Writing Your First Playbook with the Ansible VS Code Extension

A zero-touch RHDP lab where students use the Red Hat Ansible VS Code extension's AI coding assistant to generate and run Ansible playbooks and roles.

## Lab Scenario

Students build a multi-tier web and database infrastructure across three managed nodes:

- **Web tier** (node1, node2) — Apache httpd with a Jinja2-rendered status page
- **Database tier** (node3) — MariaDB server
- **All nodes** — User creation and dynamic MOTD template

## Modules

| # | Module | Description |
|---|--------|-------------|
| 01 | Meet the Coding Assistant | Explore inventory and the Ansible extension |
| 02 | Generate a Comprehensive Playbook | Use the AI assistant to generate `system_setup.yml` |
| 03 | Understand Your Playbook | Walk through the generated playbook section by section |
| 04 | Run and Verify | Run the playbook, verify results in browser tabs and CLI |
| 05 | Convert to a Role | Use Generate Role to refactor the playbook |
| 06 | Wrap-Up | Summary and next steps |

## Infrastructure

- **Platform**: AgnosticV/Babylon CNV on RHDP with Showroom content delivery
- **VMs**: 4 total — `control` (devtools-ansible), `node1`, `node2`, `node3` (rhel-9.6)
- **LLM Backend**: LiteMaaS with gpt-oss-120b (120B parameters)
- **Student UI**: VS Code tab, Control terminal (wetty), node1/node2 Web tabs (status page)

## Repository Structure

```
config/              # RHDP instance, network, firewall, secrets config
content/             # Showroom AsciiDoc modules and images
setup-automation/    # Provisioning scripts, extension vsix, prompt patches
runtime-automation/  # Per-module setup, solve, and validate playbooks
ansible-files/       # Reference playbook, inventory, and templates
ui-config.yml        # Showroom tab and module layout
site.yml             # Antora site config
```
