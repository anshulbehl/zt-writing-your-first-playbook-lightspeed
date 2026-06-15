# Current Status - June 12, 2026 Evening

## BLOCKED: SSH Port 22 Not Accessible on Nodes

### Working State
**Last working commit**: `1cdbda6` - "Add static route to pod network in setup-control.sh"

To restore: `git reset --hard 1cdbda6`

### What Works ✅
1. **Lab provisions successfully**
2. **VS Code tab** works (code-server on control:8080)
3. **Control terminal** works (wetty)
4. **Network routing configured**:
   - Static route added: `10.130.0.0/16 via 10.0.2.1 dev eth0`
   - Control (10.0.2.2) has route to pod network
5. **DNS resolution** works: All nodes resolve to 10.130.x IPs
6. **Network diagnostics** saved to `/home/rhel/network-debug.txt`

### What Doesn't Work ❌
1. **SSH from control to nodes BLOCKED**
   - Port 22 not accessible on nodes (10.130.x)
   - Firewall blocking inbound connections
2. **Ping to nodes fails** - No response from 10.130.x IPs
3. **ansible-navigator cannot reach nodes** - Connection timeout

### The Core Problem

**Network Topology**:
```
Control: 10.0.2.2 (isolated network, has vscode-8080 service/route)
         └─ Route: 10.130.0.0/16 via 10.0.2.1 ✅

node01:  10.130.9.23  (pod network, NO services/routes)
node02:  10.130.9.25  (pod network, NO services/routes)
node03:  10.130.9.28  (pod network, NO services/routes)
         └─ Firewall: Port 22 BLOCKED ❌
```

**Why port 22 is blocked**:
1. Nodes have NO services/routes in instances.yaml
2. CNV/OpenShift networking defaults to restricted inbound access
3. RHEL 9 firewalld is active and blocking SSH
4. Without explicit firewall rules, port 22 is not accessible

**Why we can't put all VMs on same subnet (10.0.2.x)**:
- The 10.0.2.x isolated network only has ONE IP available (10.0.2.2)
- When we add services/routes to all VMs, they all get duplicate IP 10.0.2.2
- This causes IP conflict and SSH loops to itself

### Attempted Fix That Broke Provisioning

**Commit `60c3317`**: "Open SSH port in firewall on all nodes"

Added to `setup-node01/02/03.sh`:
```bash
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
```

**Result**: Lab **does not provision** - hangs during setup-automation

**Why it broke** (unknown, needs investigation):
- firewalld might not be started yet when script runs
- Command syntax issue
- Missing dependency
- Timing/race condition

### Diagnostic Output

From `/home/rhel/network-debug.txt` on control:
```
Control IP Address:
    inet 10.0.2.2/24 brd 10.0.2.255 scope global dynamic noprefixroute eth0

Routing Table:
default via 10.0.2.1 dev eth0 proto dhcp src 10.0.2.2 metric 100 
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.2 metric 100 
10.130.0.0/16 via 10.0.2.1 dev eth0 

DNS Resolution Test:
10.130.9.23     node01.lab.sandbox-5hl9n-zt-ansiblebu.svc.cluster.local
10.130.9.25     node02.lab.sandbox-5hl9n-zt-ansiblebu.svc.cluster.local
10.130.9.28     node03.lab.sandbox-5hl9n-zt-ansiblebu.svc.cluster.local

Gateway reachability:
PING 10.0.2.1 (10.0.2.1) 56(84) bytes of data.
64 bytes from 10.0.2.1: icmp_seq=1 ttl=64 time=0.085 ms
64 bytes from 10.0.2.1: icmp_seq=2 ttl=64 time=0.105 ms

Adding route to pod network (10.130.0.0/16)...
✓ Route added successfully

Final routing table:
default via 10.0.2.1 dev eth0 proto dhcp src 10.0.2.2 metric 100 
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.2 metric 100 
10.130.0.0/16 via 10.0.2.1 dev eth0 
```

**Analysis**: Routing is perfect, DNS works, gateway reachable. Only problem is firewall on nodes.

### Test Results from Control

```bash
# DNS works
getent hosts node01
# 10.130.9.23     node01.lab.sandbox-5hl9n-zt-ansiblebu.svc.cluster.local

# Ping fails (firewall blocks ICMP or routing issue)
ping -c 2 10.130.9.23
# No response

# SSH port blocked
timeout 3 bash -c "cat < /dev/tcp/10.130.9.23/22"
# Connection timeout (port 22 blocked)

# SSH fails
ssh node01
# Connection timeout
```

### Why Roadshow Lab Works But Ours Doesn't

**Roadshow lab** (zt-ans-bu-roadshow01):
- Control: `aap-2.6-2-ceh-20251103` image (Ansible Automation Platform)
- node01: `rhel-9.5`, NO services/routes → 10.130.x
- **AAP CAN reach nodes** via automation controller

**Our lab**:
- Control: `devtools-ansible` image (code-server)
- node01/02/03: `rhel-9.6`, NO services/routes → 10.130.x
- **Control CANNOT reach nodes** (firewall blocks)

**Hypothesis**: 
1. AAP image has special networking capabilities
2. OR roadshow's RHEL images have SSH pre-opened in firewall
3. OR AAP uses different network path (automation controller has different access)

### Key Discovery: Cloud-Init Doesn't Work

**Finding**: `devtools-ansible` image does NOT run cloud-init!
- No `/var/log/cloud-init-output.log`
- No `/var/log/cloud-init.log`
- `systemctl status cloud-init` → not found
- **All userdata runcmd blocks are IGNORED**

**Impact**:
- Can't configure networking via userdata
- Must do everything in setup-automation scripts
- SSH password auth must be configured some other way

### Possible Solutions (Untested)

1. **Fix firewall command timing**:
   ```bash
   # Ensure firewalld is started first
   systemctl start firewalld
   systemctl enable firewalld
   firewall-cmd --permanent --add-service=ssh
   firewall-cmd --reload
   ```

2. **Use iptables directly** (bypass firewalld):
   ```bash
   iptables -I INPUT -p tcp --dport 22 -j ACCEPT
   iptables-save > /etc/sysconfig/iptables
   ```

3. **Disable firewall entirely** (not recommended):
   ```bash
   systemctl stop firewalld
   systemctl disable firewalld
   ```

4. **Add minimal service to avoid firewall**:
   - Add SSH service/route to nodes in instances.yaml
   - But this might cause them to land on 10.0.2.x with duplicate IP

5. **Use CNV NetworkPolicy** (requires OpenShift admin):
   - Define NetworkPolicy to allow control → nodes traffic
   - Might bypass VM-level firewall

6. **Change architecture**:
   - Accept nodes are unreachable from control
   - Run all playbooks via runtime-automation (different network path)
   - Students never SSH to nodes directly

### Files Changed This Session

**Key commits**:
- `83e605b`: wetty tab fix (KNOWN WORKING BASELINE)
- `049cb4e`: Add network diagnostics to setup-control.sh
- `1cdbda6`: Add static route to pod network ← **LAST WORKING**
- `60c3317`: Open SSH port in firewall ← **BREAKS PROVISIONING**

**Modified files**:
- `config/instances.yaml` - Changed node naming to node01/02/03, removed services/routes from nodes
- `setup-automation/main.yml` - Updated node loop, changed to use ansible_host
- `setup-automation/setup-control.sh` - Added network diagnostics, added static route
- `setup-automation/setup-node*.sh` - Renamed to two-digit format
- `ui-config.yml` - Updated/commented wetty node tabs
- `HANDOFF.md` - Documented all attempts and findings

### Next Steps

1. **Investigate firewall command failure**:
   - Restore to `1cdbda6`
   - Try firewall fix with different syntax/timing
   - Check firewalld logs for errors

2. **Test alternative firewall methods**:
   - iptables directly
   - systemctl start firewalld first
   - Check if firewalld is even installed on rhel-9.6

3. **Research CNV networking**:
   - How do other labs handle cross-subnet SSH?
   - Is there a NetworkPolicy approach?
   - Contact RHDP support

4. **Consider if SSH is actually needed**:
   - Do students need to SSH to nodes?
   - Or do they only use ansible-navigator from control?
   - If ansible-navigator works via different path, problem might be moot

### How to Use This Lab (Current State)

**What works**:
- ✅ Provision lab (commit `1cdbda6`)
- ✅ Access VS Code tab → edit playbooks
- ✅ Access Control tab → terminal on control VM
- ✅ View network diagnostics: `cat /home/rhel/network-debug.txt`

**What doesn't work**:
- ❌ ansible-navigator cannot run playbooks (can't reach nodes)
- ❌ Manual SSH to nodes fails
- ❌ Lab is not functional for students

**Lab is currently BLOCKED until firewall issue is resolved.**
