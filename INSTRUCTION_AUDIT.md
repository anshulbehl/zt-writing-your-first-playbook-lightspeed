# Instruction Audit Report
## Lab: zt-writing-your-first-playbook

**Date**: 2026-06-16  
**Audit scope**: Cross-reference content modules (.adoc) with actual implementation (setup scripts, validation scripts, runtime automation)

---

## Executive Summary

The lab architecture is **sound and working**, but the **instructional content has several mismatches** between what students are told to do vs what actually happens or gets validated. These gaps will cause confusion or validation failures.

**Key findings**:
1. ✅ **Lightspeed pre-configuration works** - but instructions still tell students to "connect" manually (unnecessary)
2. ⚠️ **SSH connectivity from Control tab is ambiguous** - instructions assume `ssh node1` works, but actual network setup may require IP addresses or /etc/hosts validation
3. ⚠️ **Validation scripts check for specific playbook structure** - but instructions give students freedom to generate playbooks however they want
4. ✅ **File sharing works** - single VM architecture eliminates the problem
5. ⚠️ **Module 04 has TODO placeholder** - section about Claude skills is incomplete

---

## Module 01: Meet Ansible Lightspeed

### Content file
`content/modules/ROOT/pages/01-playbook-inventory.adoc`

### Issues Found

#### Issue 1.1: Lightspeed "Connect" instruction is unnecessary
**Location**: Lines 62-75 (Task 1)

**What the instructions say**:
```
Open the Command Palette with Ctrl+Shift+P and type:
  Ansible: Connect to Lightspeed

Select the option and confirm the connection succeeds.
```

**What actually happens**:
- `setup-control.sh` lines 130-156 configure Lightspeed automatically via `settings.json`
- Uses `rhcustom` provider with LiteMaaS endpoint (no Red Hat SSO login required)
- Extension auto-activates on first VS Code load with settings already applied

**Impact**: Students will execute a command that does nothing (already connected) or may see confusing UX because Lightspeed is pre-authenticated.

**Recommendation**: 
- Change Task 1 to "Verify Lightspeed is connected"
- Instructions should say: "Look at the bottom status bar of VS Code. You should see the Ansible Lightspeed icon showing a connected state (green). Lightspeed is pre-configured in this lab to use LiteMaaS — you do not need to log in."
- Remove the "Connect to Lightspeed" command palette step (already done by setup automation)

#### Issue 1.2: TIP note mentions LiteMaaS correctly
**Location**: Lines 72-75

**Status**: ✅ **CORRECT**

This TIP is accurate:
```
Lightspeed is pre-configured in this lab to use a LiteMaaS model endpoint — 
Red Hat AI's Model-as-a-Service platform. You do not need to log in or 
provide any credentials; the API key is already set up for you.
```

Matches `setup-control.sh` configuration.

---

## Module 02: Generate a Comprehensive Playbook

### Content file
`content/modules/ROOT/pages/02-generate-comprehensive-playbook.adoc`

### Issues Found

#### Issue 2.1: Playbook generation flexibility vs validation strictness
**Location**: Lines 32-89 (Task 1 - comprehensive prompt construction)

**What the instructions say**:
- Students are encouraged to "expand on" a starter prompt
- Prompt is presented as a template they can customize
- "The more complete your prompt, the more accurate Lightspeed's output will be"

**What validation expects** (`02-generate-comprehensive-playbook/validation.yml` lines 26-36):
```yaml
grep -q "hosts: all" ... && \
grep -q "become: true" ... && \
grep -q "vars:" ... && \
grep -q "user_name" ... && \
grep -q "when: inventory_hostname in groups\['web'\]" ... && \
grep -q "handlers:" ... && \
grep -q "ansible.builtin.template" ...
```

**Mismatch**: 
- Validation checks for **exact string matches** (`when: inventory_hostname in groups['web']`)
- If Lightspeed generates a functionally equivalent but differently worded playbook (e.g., `when: "'web' in group_names"`), validation will fail
- Students may generate valid playbooks that don't match the regex patterns

**Impact**: Students could complete the task correctly (working playbook) but fail validation because Lightspeed phrased it differently.

**Recommendation**:
1. **Option A - Make validation flexible**: Check for presence of conditionals, handlers, template tasks without exact string matching
2. **Option B - Make instructions prescriptive**: Tell students the exact prompt to use (remove customization freedom) so Lightspeed output is predictable
3. **Option C - Add solve-before-validate pattern**: If validation fails, students can click "Solve" to get the canonical version, then re-run validation

#### Issue 2.2: Handler mention without teaching handlers
**Location**: Line 177-181 (Task 4, explain handlers section)

**What instructions assume**:
```
Scroll to the `handlers:` section in `system_setup.yml`
Select the entire `handlers:` block (including the handler name and task)
```

**What validation checks** (`validation.yml` line 32):
```yaml
grep -q "handlers:" /home/{{ USER }}/ansible-files/system_setup.yml
```

**Issue**: 
- The prompt template (lines 62-75) does NOT mention handlers
- Students are told to request tasks for kernel updates, user creation, package install, service start, template deploy
- **None of these explicitly require a handler** in the starter prompt
- Yet validation expects `handlers:` to exist, and Task 4 tells students to explain the handlers section

**What actually happens**:
- If Lightspeed generates a playbook with `systemd` service tasks, it may or may not include handlers
- Modern Ansible best practice often uses `ansible.builtin.systemd: state=started enabled=yes` directly without handlers for simple service starts

**Impact**: 
- Students may generate a working playbook without handlers (valid Ansible)
- Validation will fail because handlers section is missing
- Task 4 instructions will be confusing ("scroll to the handlers section" — what if there isn't one?)

**Recommendation**:
1. **Option A**: Explicitly add "use a handler to restart Apache if the config changes" to the prompt template in Task 1
2. **Option B**: Remove handler requirement from validation (line 32) and make Task 4 conditional ("If your playbook includes handlers...")
3. **Option C**: Provide a more detailed prompt that explicitly requests handler usage

---

## Module 03: Run and Verify the Playbook

### Content file
`content/modules/ROOT/pages/03-playbook-run-it.adoc`

### Issues Found

#### Issue 3.1: SSH node connectivity assumptions
**Location**: Lines 67-92 (Task 2 - verify user creation via SSH)

**What the instructions say**:
```bash
ssh node1 id padawan
ssh node2 id padawan
ssh node3 id padawan
```

**What the architecture provides**:
- `config/instances.yaml`: All VMs on same isolated network (10.0.2.x) via services/routes configuration
- `setup-automation/main.yml`: Populates `/etc/hosts` on control VM with node IPs using Ansible facts
- `ansible-files/ansible.cfg`: SSH connection timeout configured
- `ui-config.yml`: Wetty tabs for Node1/Node2/Node3 exist

**What validation does** (`03-playbook-run-it/validation.yml`):
- Lines 6-16: Check user `padawan` exists on all hosts (uses Ansible, not SSH commands)
- Lines 33-43: Check httpd installed and running on web group (uses Ansible, not SSH)

**Ambiguity**:
1. Do students run `ssh node1` from the **Control tab wetty terminal**?
2. Does `/etc/hosts` on the control VM include node1/node2/node3 entries at the time students reach module 03?
3. Is SSH password (`ansible123!`) configured for rhel user on nodes, or is it key-based auth?

**From handoff.md** (lines 195-210):
- setup-automation/main.yml generates SSH keypair and distributes to all VMs
- This suggests **key-based auth**, not password
- `/etc/hosts` is populated during setup-automation run

**Likely outcome**: SSH commands will work IF:
- wetty Control tab connects to control VM (yes, per handoff line 106)
- `/etc/hosts` has node entries (yes, per main.yml)
- SSH keys are in place (yes, per main.yml)

**Recommendation**:
- ✅ Instructions are probably fine, but should include a **verification step in Task 2**:
  ```
  Before SSHing to nodes, verify hostname resolution works:
  
  ping -c 1 node1
  
  You should see a reply from the node's IP address (10.0.2.x). If ping fails, 
  /etc/hosts may not be configured correctly.
  ```

#### Issue 3.2: httpd verification on node3 uses error-suppression pattern
**Location**: Lines 129-139 (Task 3 - verify httpd NOT on database)

**What the instructions say**:
```bash
ssh node3 systemctl is-active httpd 2>&1 || echo "httpd not installed (expected)"
```

**What validation does** (`03-playbook-run-it/validation.yml` lines 57-71):
```yaml
- name: Check httpd is not installed on database servers
  ansible.builtin.command:
    cmd: rpm -q httpd
  failed_when: false
  register: r_httpd_db

- name: Fail if httpd is installed on database server
  ansible.builtin.fail:
    msg: "httpd should not be installed on {{ inventory_hostname }} (database group)"
  when: r_httpd_db.rc == 0
```

**Mismatch**:
- Instructions use `systemctl is-active` (checks if service is running)
- Validation uses `rpm -q httpd` (checks if package is installed)

**Scenario where they differ**:
- If httpd is installed but stopped/disabled, `systemctl is-active httpd` returns "inactive" (rc=3)
- But `rpm -q httpd` returns success (rc=0) because package exists
- Instructions would say "httpd not installed" but validation would fail

**Impact**: Minor — if students follow the playbook prompt correctly, httpd won't be installed on node3 at all, so both checks pass. But instructions are technically checking the wrong thing.

**Recommendation**:
- Change line 132 to:
  ```bash
  ssh node3 rpm -q httpd 2>&1 || echo "httpd not installed (expected)"
  ```
  This matches what validation checks.

#### Issue 3.3: Idempotency explanation task references wrong output
**Location**: Lines 219-226 (Task 5 - explain playbook for idempotency info)

**What the instructions say**:
```
Switch to the VS Code tab, open system_setup.yml, select all the content, 
right-click, and choose Ansible Lightspeed → Explain. Read the explanation 
and look for mentions of idempotency and state checking.
```

**Issue**:
- This asks Lightspeed to explain the **entire playbook**, not the concept of idempotency
- Lightspeed's "Explain" feature describes what the code does, not necessarily why Ansible is idempotent
- A better learning approach would be to explain **why the second run showed ok instead of changed**

**Recommendation**:
- Remove this substep from Task 5 (lines 226-227)
- The collapsible "What is idempotency?" section (lines 197-205) already explains it well
- Students don't need Lightspeed to re-explain the playbook — they just ran it twice and saw the difference

---

## Module 04: Wrap-Up and Next Steps

### Content file
`content/modules/ROOT/pages/04-wrap-up.adoc`

### Issues Found

#### Issue 4.1: TODO placeholder for Claude skills content
**Location**: Lines 109-119

**What's there**:
```asciidoc
.🤖 TODO: Add content about Claude skills here
[%collapsible]
====
*Placeholder for Claude skills and custom automation content.*

[NOTE]
====
This section is reserved for discussing how to extend this lab with Claude Code 
skills, custom workflows, or advanced LLM-assisted automation patterns.
====
====
```

**Impact**: 
- Incomplete content in final module
- Doesn't match the polish of the rest of the lab

**Recommendation**:
- Either **remove this collapsible entirely** (the other three — Galaxy, Roles, CI/CD — provide good next steps)
- Or **fill it in** with content about:
  - How students can use Claude Code to generate more Ansible playbooks locally
  - Reference to RHDP Lab Foundry skills (if appropriate for audience)
  - How LLM-assisted workflows (Lightspeed, Claude, ChatGPT) fit into modern automation practices

---

## Summary of Recommended Fixes

### High Priority (Breaks Validation)

1. **Module 02, Issue 2.1** - Validation regex too strict for Lightspeed variability
   - Fix validation to check for presence of features, not exact string matches
   - OR: Make prompt template mandatory (not "expand on this") so output is predictable

2. **Module 02, Issue 2.2** - Handler requirement not in prompt template
   - Add handler usage to the prompt template in Task 1
   - OR: Remove handler requirement from validation

### Medium Priority (Confusing UX)

3. **Module 01, Issue 1.1** - "Connect to Lightspeed" command unnecessary
   - Change to "Verify Lightspeed is connected" (read-only check)
   - Remove command palette action

4. **Module 03, Issue 3.2** - Verification command doesn't match validation check
   - Change `systemctl is-active httpd` to `rpm -q httpd` in instructions

### Low Priority (Polish)

5. **Module 03, Issue 3.1** - Add hostname resolution verification
   - Add `ping -c 1 node1` step before first SSH command

6. **Module 03, Issue 3.3** - Lightspeed explain step doesn't add value
   - Remove "explain the playbook" substep from Task 5

7. **Module 04, Issue 4.1** - Incomplete TODO section
   - Complete or remove the Claude skills collapsible

---

## Files Referenced

### Content
- `content/modules/ROOT/pages/01-playbook-inventory.adoc`
- `content/modules/ROOT/pages/02-generate-comprehensive-playbook.adoc`
- `content/modules/ROOT/pages/03-playbook-run-it.adoc`
- `content/modules/ROOT/pages/04-wrap-up.adoc`

### Runtime Automation
- `runtime-automation/01-playbook-inventory/validation.yml`
- `runtime-automation/02-generate-comprehensive-playbook/validation.yml`
- `runtime-automation/02-generate-comprehensive-playbook/solve.yml`
- `runtime-automation/03-playbook-run-it/validation.yml`

### Setup Automation
- `setup-automation/setup-control.sh` (lines 130-156: Lightspeed config)
- `setup-automation/main.yml` (populates /etc/hosts)

### Configuration
- `config/instances.yaml` (network placement via services/routes)
- `ui-config.yml` (tab definitions)

---

## Next Steps

1. Review this audit with stakeholders
2. Decide on fix approach for high-priority issues (prescriptive prompts vs flexible validation)
3. Update .adoc files with corrections
4. Re-test validation scripts against corrected instructions
5. Complete or remove TODO section in module 04
