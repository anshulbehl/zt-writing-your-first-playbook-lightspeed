# AgnosticV/Babylon Considerations

## Why Direct Download Instead of Git Clone

The setup script uses `curl` to download individual files from GitHub's raw content API instead of using `git clone` or sparse checkout. This design choice is specifically for AgnosticV/Babylon environments.

## Benefits for AgnosticV/Babylon

### 1. No Git Dependency
- RHEL base images may not have `git` installed by default
- Avoids need to install additional packages during setup
- `curl` is part of base RHEL installation

### 2. Faster and More Reliable
- Downloads only the exact files needed (~4 files total)
- No need to initialize git repository or pull history
- Smaller network footprint during provisioning

### 3. Simpler Error Handling
- Each file download has its own retry logic
- Easier to debug which specific file failed
- No git authentication or SSH key concerns

### 4. Environment Agnostic
- Works in restricted network environments
- No git protocol requirements (just HTTPS)
- Compatible with proxy configurations common in enterprise

## Download Mechanism

```bash
# GitHub repository base URL
REPO_URL="https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main"

# Download with retry logic
download_file() {
    local url=$1
    local dest=$2
    local max_attempts=3
    
    for attempt in $(seq 1 $max_attempts); do
        if curl -fsSL "$url" -o "$dest"; then
            return 0
        fi
        sleep 2
    done
    return 1
}
```

## Files Downloaded

From `ansible-files/` directory:
1. `ansible.cfg` - Ansible configuration
2. `ansible-navigator.yml` - Navigator configuration
3. `inventory` - Pre-configured inventory
4. `templates/motd.j2` - Template file

**Excluded**: `README.md`, `.gitignore`, `system_setup.yml`

## Integration with AgnosticV Lifecycle

This approach fits naturally into the AgnosticV provisioning flow:

1. **Infrastructure Creation** - CNV creates VMs from config/instances.yaml
2. **Cloud-init** - Sets up basic user/SSH (defined in instances.yaml userdata)
3. **Setup Automation** - AgnosticV runs setup-automation/main.yml which:
   - Distributes setup-*.sh scripts to each VM
   - Executes them with proper environment variables (SATELLITE_*, etc.)
   - **setup-control.sh downloads files from GitHub at this stage**
4. **Runtime Automation** - Student progresses through modules

## When Files are Updated

To update the student environment files:
1. Edit files in `ansible-files/` directory in the main repo
2. Commit and push to main branch
3. Next lab provision automatically gets the new files

No need to:
- Update setup scripts
- Rebuild images
- Clear caches
- Coordinate separate repository

## Fallback Strategy

If GitHub is unreachable during provisioning, the setup script will:
1. Retry each file download 3 times
2. Fail with clear error message indicating which file couldn't be downloaded
3. AgnosticV setup will fail (expected behavior - can't proceed without configs)

Alternative for offline environments:
- Host files on internal git server
- Change `REPO_URL` to point to internal server
- Same download mechanism works

## Migration to Red Hat Org

When moving to the official Red Hat Ansible organization:
1. Update `REPO_URL` in setup-control.sh to new org location
2. Push the change
3. All future provisions use the new location

Single line change:
```bash
# Change from:
REPO_URL="https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main"

# To:
REPO_URL="https://raw.githubusercontent.com/redhat-ansible/zt-writing-your-first-playbook/main"
```
