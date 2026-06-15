# Current Status - June 15, 2026

## Fixes Applied (per FIXES.md)

### Root Cause
The SSH block was at the **Kubernetes NetworkPolicy layer**, not the VM OS.
Live evidence confirmed: no firewalld on nodes, sshd listening on 0.0.0.0:22,
control OS firewall wide open (zone trusted, target ACCEPT). The repo's
`firewall.yaml` declared egress `{80, 443}` only, which replaced the platform
default that permitted VM-to-VM SSH.

### Changes Made

1. **`config/firewall.yaml`** — Added egress TCP/22 (control → nodes SSH),
   egress UDP+TCP/53 (DNS), and ingress TCP/22.

2. **`setup-automation/setup-node01.sh`**, **node02.sh**, **node03.sh** —
   Removed dead firewalld/iptables code. No firewalld exists on the rhel-9.6
   nodes; the commands failed with `command not found` and risked hanging
   provisioning.

3. **`setup-automation/setup-control.sh`** — Removed static route hack
   (`ip route add 10.130.0.0/16 via 10.0.2.1`). Redundant under KubeVirt
   masquerade networking.

### Verification (after provisioning)

```bash
nc -vz <node01-pod-ip> 22          # expect: open
ssh rhel@node01 hostname           # expect: node01
ansible -i inventory all -m ping   # expect: SUCCESS
```

Do NOT use `ping` — masquerade doesn't forward ICMP. Use `nc -vz` on port 22.

### If Still Blocked

See FIXES.md "If still blocked" section for escalation steps and NetworkPolicy
diagnostics to gather.
