import sys

with open(sys.argv[1], 'rb') as f:
    content = f.read()

LINT_RULES = (
    b'Always use ansible.builtin.dnf for package management. Never use apt modules. '
    b'Always use state: present, NEVER state: latest even for security updates. '
    b'Always set mode: on file, template, and copy tasks (e.g. mode: "0644"). '
    b'Use human-readable handler names like "Restart Apache", not snake_case. '
    b'Use true/false for booleans, never yes/no. '
    b'Only include parameters explicitly requested. Do not add extra parameters like groups, shell, or home path. '
    b'When a task should trigger a handler, include notify: with the exact handler name. '
    b'Always end YAML files with a trailing newline.'
)

# Playbook prompt: backtick-terminated string, ends with: playbook.`;
old_playbook = b'You answer with just an Ansible playbook.`;'
new_playbook = b'You answer with just an Ansible playbook.\\n' + LINT_RULES + b'`;'
assert old_playbook in content, "Playbook prompt not found"
content = content.replace(old_playbook, new_playbook, 1)

# Role prompt: rewrite to produce a YAML mapping with tasks, handlers, vars.
# The original prompt only asks for tasks/main.yml. We replace the entire
# prompt so the LLM returns all three sections as top-level YAML keys.
# cleanAnsibleOutput() yaml.load/dump preserves the mapping structure,
# then the patched generateRole() parser (below) splits it into files.
old_role_prompt = (
    b'You are an ansible expert optimized to generate Ansible roles.\n'
    b'Generate ONLY the tasks/main.yml file content as a YAML array of tasks.\n'
    b'Do NOT include role_name, do NOT include document separators (---), do NOT include multiple YAML documents.\n'
    b'Output ONLY a single YAML array starting with "- name:" for each task.\n'
    b'Prefix your comments with the hash character.'
)
new_role_prompt = (
    b'You are an ansible expert optimized to generate Ansible roles.\n'
    + LINT_RULES + b'\n'
    b'Output a YAML mapping with exactly three top-level keys: tasks, handlers, vars.\n'
    b'tasks: a YAML array of tasks, each starting with "- name:".\n'
    b'handlers: a YAML array of handlers for notify triggers.\n'
    b'vars: a YAML mapping of variable definitions used by the tasks.\n'
    b'Do NOT include document separators (---).\n'
    b'Do NOT wrap output in code fences.\n'
    b'Prefix comments with the hash character.'
)
assert old_role_prompt in content, "Role prompt not found"
content = content.replace(old_role_prompt, new_role_prompt, 1)

# Role generation: replace the single-file builder with a multi-file parser.
# After cleanAnsibleOutput yaml.load/dump, the content is a well-formatted
# YAML mapping. Split on top-level keys and dedent each section into its
# own file. Falls back to tasks-only if the LLM ignores the mapping format.
old_files_block = (
    b'const files = [\n'
    b'        {\n'
    b'          path: "tasks/main.yml",\n'
    b'          content: llmResponse.content,\n'
    b'          file_type: "task" /* Task */\n'
    b'        }\n'
    b'      ];'
)
new_files_block = (
    b'const _raw = llmResponse.content;\n'
    b'      const _typeMap = {"tasks":"task","handlers":"handler","vars":"var"};\n'
    b'      const files = [];\n'
    b'      const _parts = _raw.split(/^(?=\\w+:\\s*$)/m);\n'
    b'      for (const _part of _parts) {\n'
    b'        const _match = _part.match(/^(\\w+):\\s*\\n([\\s\\S]*)/);\n'
    b'        if (_match && _typeMap[_match[1]]) {\n'
    b'          const _body = _match[2].replace(/^  /gm, "").trim();\n'
    b'          if (_body) files.push({path: _match[1] + "/main.yml", content: "---\\n" + _body + "\\n", file_type: _typeMap[_match[1]]});\n'
    b'        }\n'
    b'      }\n'
    b'      if (files.length === 0) {\n'
    b'        files.push({ path: "tasks/main.yml", content: _raw, file_type: "task" });\n'
    b'      }'
)
assert old_files_block in content, "Role files block not found"
content = content.replace(old_files_block, new_files_block, 1)

# Role generation: skip the "File already exists" check so re-generating
# a role with the same name overwrites silently instead of spamming errors.
old_exists = b'if (await fileExists(fileUri)) {'
new_exists = b'if (false && fileExists(fileUri)) {'
assert old_exists in content, "Role file-exists check not found"
content = content.replace(old_exists, new_exists, 1)

with open(sys.argv[1], 'wb') as f:
    f.write(content)

print("Patched: dnf prompts, multi-file role generation, role overwrite")
