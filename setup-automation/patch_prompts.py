import sys

with open(sys.argv[1], 'rb') as f:
    content = f.read()

DNF_INSTRUCTION = b'Always use ansible.builtin.dnf for package management. Never use apt modules.'

# Playbook prompt: backtick-terminated string, ends with: playbook.`;
old_playbook = b'You answer with just an Ansible playbook.`;'
new_playbook = b'You answer with just an Ansible playbook.\\n' + DNF_INSTRUCTION + b'`;'
assert old_playbook in content, "Playbook prompt not found"
content = content.replace(old_playbook, new_playbook, 1)

# Role prompt: template literal with real newlines
old_role = b'You are an ansible expert optimized to generate Ansible roles.\n'
new_role = b'You are an ansible expert optimized to generate Ansible roles.\n' + DNF_INSTRUCTION + b'\n'
assert old_role in content, "Role prompt not found"
content = content.replace(old_role, new_role, 1)

# Role generation: skip the "File already exists" check so re-generating
# a role with the same name overwrites silently instead of spamming errors.
old_exists = b'if (await fileExists(fileUri)) {'
new_exists = b'if (false && fileExists(fileUri)) {'
assert old_exists in content, "Role file-exists check not found"
content = content.replace(old_exists, new_exists, 1)

with open(sys.argv[1], 'wb') as f:
    f.write(content)

print("Patched system prompts for dnf and role overwrite")
