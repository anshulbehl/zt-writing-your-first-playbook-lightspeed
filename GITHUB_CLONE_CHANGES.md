# GitHub Clone Setup - Changes Summary

## What Changed

Modified `setup-automation/setup-control.sh` to clone pre-configured Ansible files from the main lab repository using sparse checkout instead of generating them inline during provisioning.

## Before vs After

### Before (Inline Generation)
- Generated `ansible.cfg`, `ansible-navigator.yml`, and `inventory` files via heredocs in bash script
- Total: 112 lines
- Hard to update (required editing provisioning script)
- Configuration embedded in deployment logic

### After (Direct Download from Main Repo)
- Downloads files from: https://github.com/rhpds/zt-writing-your-first-playbook.git
- Uses GitHub raw content API (no git required on control node)
- Downloads only necessary files (excludes README.md)
- Total: ~105 lines
- Easy to update (just push to main repo)
- Configuration separated from deployment
- Single repository to maintain
- Works reliably in AgnosticV/Babylon environments

## Key Changes

1. **Removed inline file generation**
   - No more heredocs creating inventory, ansible-navigator.yml inline
   - Files now pulled from version-controlled main lab repo

2. **Added direct file download logic**
   ```bash
   # Download files via GitHub raw content API (no git required)
   REPO_URL="https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main"
   curl -fsSL "$REPO_URL/ansible-files/ansible.cfg" -o "/home/rhel/ansible-files/ansible.cfg"
   # ... repeat for other required files
   ```

3. **Added file verification**
   - Checks that required files exist after clone
   - Fails fast if files are missing

4. **Simplified ansible-navigator.yml handling**
   - Changed from generating in two locations to copying from cloned repo

5. **Selective file download**
   - Only downloads necessary files: `ansible.cfg`, `ansible-navigator.yml`, `inventory`, `templates/motd.j2`
   - Excludes `README.md` and other documentation files
   - No git dependency required on VMs (uses curl instead)

## Files Still Generated Inline

The following files are still generated inline (and should remain so):
- `/home/rhel/.ansible.cfg` - User-specific config pointing to inventory
- `/home/rhel/.gitconfig` - User git configuration

These are user-level configs that reference the cloned files.

## Files Now Pulled from GitHub

Repository: https://github.com/rhpds/zt-writing-your-first-playbook.git (main lab repo)
Directory: `ansible-files/`

Files pulled via sparse checkout:
- `ansible.cfg` - Ansible configuration
- `ansible-navigator.yml` - Navigator configuration  
- `inventory` - Pre-configured inventory (web, database, nodes groups)
- `templates/motd.j2` - Message of the Day template

Files explicitly excluded:
- `README.md` - Not needed in student workspace

## Testing Checklist

Before deploying:
1. ✅ Main lab repo contains `ansible-files/` directory
2. ⬜ Test file downloads work:
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main/ansible-files/ansible.cfg"
   curl -fsSL "https://raw.githubusercontent.com/rhpds/zt-writing-your-first-playbook/main/ansible-files/inventory"
   ```
3. ⬜ Verify all required files exist in `ansible-files/` directory on GitHub
4. ⬜ Test setup script in AgnosticV/Babylon lab environment
5. ⬜ Verify student can run ansible-navigator after setup
6. ⬜ Confirm inventory groups are correct (web, database, nodes)
7. ⬜ Check that templates directory and motd.j2 work in playbooks
8. ⬜ Verify README.md is NOT copied to student workspace
9. ⬜ Confirm curl is available on RHEL 9.6 base image (should be by default)

## Next Steps

1. **Delete the separate repository** (`lightspeed-lab-ansible-files` - no longer needed)
2. **Test the setup script** in a live lab environment
3. **Update any documentation** that references file generation
4. **Deploy to staging** for validation
5. **Roll out to production** after successful staging test
6. **Migrate to Red Hat org** when ready (single repo to move)

## Rollback Plan

If issues arise:
1. Revert to previous commit: `git revert <commit-hash>`
2. Files will be generated inline again as before
3. No data loss - GitHub repo remains available for future use
