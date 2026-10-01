#!/usr/bin/env python3
"""Verify pinned GitHub Actions and the desired repository settings manifest.

Offline and read-only; CI runs it on every pull request. It follows the
workflow policy of TamaT-LLC/depgraph-cli (`github-actions-policy-v1`):

- every `uses:` in .github/workflows is pinned to the commit SHA listed in
  .github/actions-policy.json, carries a `# vX.Y.Z` comment of the reviewed
  major version, and the policy lists no unused action;
- workflows keep read-only defaults: no pull_request_target, no write-all, no
  YAML escapes, top-level permissions of `contents: read` or `{}`, no secrets
  or write permissions in pull request workflows, and checkout without
  persisted credentials;
- .github/settings-desired-v1.json is valid (see github_settings_manifest.py),
  every required check comes from a pull request job without path filters or
  from CodeQL default setup, and every deployment environment used by a
  workflow is declared.

`github_settings_drift.py` compares the manifest with the live settings.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

import github_settings_manifest as manifest

ROOT = pathlib.Path(__file__).resolve().parent.parent
POLICY_FILE = '.github/actions-policy.json'
WORKFLOW_DIR = '.github/workflows'
POLICY_SCHEMA = 'github-actions-policy-v1'
POLICY_ENTRY_KEYS = ('identity', 'sha', 'reviewed_upstream_ref')

SHA = re.compile(r'[0-9a-f]{40}\Z')
ACTION_IDENTITY = re.compile(r'[A-Za-z0-9._-]{1,128}/[A-Za-z0-9._-]{1,128}\Z')
MAJOR_REF = re.compile(r'v([0-9]+)\Z')
VERSION_COMMENT = re.compile(r'v([0-9]+)(?:\.[0-9]+){0,2}\Z')
USES_LINE = re.compile(r'(?P<indent> *)(?P<dash>- +)?uses: *(?P<spec>\S+) *(?:# *(?P<comment>\S*))? *\Z')
USES_KEY = re.compile(r'''(?<![A-Za-z0-9_])["']?uses["']? *:''')
YAML_ESCAPE = re.compile(r'\\(?:x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})')
PERSIST_FALSE = re.compile(r' *persist-credentials: *false *(?:#.*)?\Z')
PATH_FILTERS = ('paths', 'paths-ignore')
READ_ONLY_PERMISSIONS = ([], ['contents: read'])


class Workflow:
    """Facts about one workflow file that the settings checks need."""

    def __init__(self, name, text):
        self.name = name
        self.lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
        self.text = '\n'.join(self.lines)
        self.triggers = _block_keys(self.lines, 'on')
        self.jobs = _jobs(self.lines)

    @property
    def is_pull_request(self):
        return 'pull_request' in self.triggers

    def required_check_names(self):
        if not self.is_pull_request or set(self.triggers['pull_request']) & set(PATH_FILTERS):
            return set()
        return {job['check'] for job in self.jobs.values()}

    def environments(self):
        return {job['environment'] for job in self.jobs.values() if job['environment']}


def _indent(line):
    return len(line) - len(line.lstrip(' '))


def _code(line):
    return line.split('#', 1)[0].rstrip()


def _scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
        return value[1:-1]
    return value


def _top_level(lines, key):
    """Return the lines of a top-level block mapping, or None when absent."""
    for index, line in enumerate(lines):
        if _code(line) == key + ':':
            block = []
            for child in lines[index + 1:]:
                if _code(child) and _indent(child) == 0:
                    break
                block.append(child)
            return block
    return None


def _block_keys(lines, key):
    """Map each child key of a top-level block to its own child keys."""
    keys = {}
    current = None
    for line in _top_level(lines, key) or []:
        code = _code(line)
        if not code.strip():
            continue
        name = code.strip().split(':', 1)[0]
        if _indent(line) == 2:
            current = keys.setdefault(name, [])
        elif _indent(line) == 4 and current is not None:
            current.append(name)
    return keys


def _jobs(lines):
    """Map each job id to its check name (`name:` or the id) and deployment environment."""
    jobs = {}
    current = None
    in_environment = False
    for line in _top_level(lines, 'jobs') or []:
        code = _code(line)
        if not code.strip():
            continue
        indent = _indent(line)
        key, _, value = code.strip().partition(':')
        if indent == 2:
            current = jobs.setdefault(key, {'check': key, 'environment': None})
            in_environment = False
        elif current is not None and indent == 4:
            in_environment = key == 'environment' and not _scalar(value)
            if key == 'name':
                current['check'] = _scalar(value)
            elif key == 'environment' and _scalar(value):
                current['environment'] = _scalar(value)
        elif current is not None and indent == 6 and in_environment and key == 'name':
            current['environment'] = _scalar(value)
    return jobs


def load_policy(data):
    """Return ({identity: (sha, major)}, errors) for a parsed Actions policy."""
    errors = []
    if not isinstance(data, dict) or set(data) != {'schema_version', 'actions'} \
            or data['schema_version'] != POLICY_SCHEMA or not isinstance(data['actions'], list) \
            or not data['actions']:
        return {}, [f'{POLICY_FILE}: must be a {POLICY_SCHEMA} object with a nonempty actions list']
    pins = {}
    previous = None
    for index, entry in enumerate(data['actions']):
        valid = isinstance(entry, dict) and set(entry) == set(POLICY_ENTRY_KEYS) \
            and all(isinstance(entry[key], str) for key in POLICY_ENTRY_KEYS)
        major = MAJOR_REF.match(entry['reviewed_upstream_ref']) if valid else None
        if not valid or not ACTION_IDENTITY.match(entry['identity']) or not SHA.match(entry['sha']) \
                or major is None or (previous is not None and previous >= entry['identity']):
            errors.append(f'{POLICY_FILE}: actions[{index}] must be a sorted, unique owner/repo '
                          'pinned to a 40-character lowercase SHA with a vN reviewed_upstream_ref')
            continue
        previous = entry['identity']
        pins[entry['identity']] = (entry['sha'], int(major.group(1)))
    return pins, errors


def check_workflow(workflow, pins):
    """Return (errors, used action identities) for one workflow."""
    name = f'{WORKFLOW_DIR}/{workflow.name}'
    errors = []
    used = set()
    if 'pull_request_target' in workflow.text:
        errors.append(f'{name}: pull_request_target is forbidden')
    if YAML_ESCAPE.search(workflow.text):
        errors.append(f'{name}: YAML hex or unicode escapes are forbidden')
    if not workflow.triggers:
        errors.append(f'{name}: triggers must be declared as a top-level `on:` block')
    errors += _check_permissions(name, workflow)
    if workflow.is_pull_request and _uses_expression_context(workflow.text, 'secrets'):
        errors.append(f'{name}: pull request workflows must not read secrets')
    for index, line in enumerate(workflow.lines):
        match = USES_LINE.match(line)
        if match is None:
            if USES_KEY.search(_code(line)):
                errors.append(f'{name}:{index + 1}: noncanonical uses key')
            continue
        errors += _check_uses(f'{name}:{index + 1}', match, pins, used)
        if match.group('spec').startswith('actions/checkout@') \
                and not any(PERSIST_FALSE.match(step) for step in _step_block(workflow.lines, index)):
            errors.append(f'{name}:{index + 1}: actions/checkout must set persist-credentials: false')
    return errors, used


def _check_permissions(name, workflow):
    errors = []
    write_scopes = []
    for line in workflow.lines:
        key, separator, value = _code(line).strip().partition(':')
        if not separator:
            continue
        if _scalar(key) == 'permissions' and value.strip() not in ('', '{}'):
            errors.append(f'{name}: permissions must be a block mapping or {{}}, not {value.strip()!r}')
        elif _scalar(value) == 'write':
            write_scopes.append(key.strip())
    top = _top_level(workflow.lines, 'permissions')
    inline_empty = any(_code(line) == 'permissions: {}' for line in workflow.lines)
    entries = sorted(_code(line).strip() for line in (top or []) if _code(line).strip())
    if top is None and not inline_empty:
        errors.append(f'{name}: top-level permissions must be declared')
    elif entries not in READ_ONLY_PERMISSIONS:
        errors.append(f'{name}: top-level permissions must be `contents: read` or {{}}')
    if workflow.is_pull_request and write_scopes:
        errors.append(f'{name}: pull request workflows must not request write permissions {write_scopes}')
    return errors


def _uses_expression_context(text, context):
    pattern = re.compile(r'(?<![A-Za-z0-9_])' + context + r'(?![A-Za-z0-9_])', re.IGNORECASE)
    return any(pattern.search(part.split('}}', 1)[0]) for part in text.split('${{')[1:])


def _check_uses(location, match, pins, used):
    spec = match.group('spec')
    if spec.startswith('./'):
        return []
    identity, _, revision = spec.rpartition('@')
    if identity not in pins or pins[identity][0] != revision:
        return [f'{location}: uses mutable, unreviewed, or unlisted action {spec}']
    used.add(identity)
    comment = VERSION_COMMENT.match(match.group('comment') or '')
    if comment is None or int(comment.group(1)) != pins[identity][1]:
        return [f'{location}: {identity} needs a `# v{pins[identity][1]}.x.y` version comment']
    return []


def _step_block(lines, index):
    """Return the lines of the step that contains lines[index]."""
    start = index
    if not lines[index].lstrip(' ').startswith('- '):
        start = next((j for j in range(index - 1, -1, -1)
                      if lines[j].lstrip(' ').startswith('- ') and _indent(lines[j]) < _indent(lines[index])), index)
    dash = _indent(lines[start])
    block = [lines[start]]
    for line in lines[start + 1:]:
        if line.strip() and _indent(line) <= dash:
            break
        block.append(line)
    return block


def verify_actions(root):
    """Return (errors, workflows) for the Actions policy and every workflow."""
    root = pathlib.Path(root)
    try:
        pins, errors = load_policy(json.loads((root / POLICY_FILE).read_text()))
    except (OSError, ValueError) as error:
        return [f'{POLICY_FILE}: cannot be read as JSON: {error}'], []
    paths = sorted(p for p in (root / WORKFLOW_DIR).iterdir() if p.suffix in ('.yml', '.yaml'))
    workflows = []
    used = set()
    for path in paths:
        if path.is_symlink() or not path.is_file():
            errors.append(f'{WORKFLOW_DIR}/{path.name}: must be a regular file')
            continue
        workflow = Workflow(path.name, path.read_text())
        workflow_errors, workflow_used = check_workflow(workflow, pins)
        errors += workflow_errors
        used |= workflow_used
        workflows.append(workflow)
    if not workflows:
        errors.append(f'{WORKFLOW_DIR}: no workflow found')
    for identity in sorted(set(pins) - used):
        errors.append(f'{POLICY_FILE}: {identity} is not used by any workflow')
    return errors, workflows


def verify_settings(root, workflows):
    """Return errors of the settings manifest and its consistency with the workflows."""
    data, errors = manifest.load(root)
    if data is None:
        return errors
    checks = set().union(*(w.required_check_names() for w in workflows))
    code_scanning = data['security']['code_scanning']
    for ruleset in data['rulesets']:
        for check in ruleset['required_checks']:
            context = check['context']
            source = (check['source_app_id'], check['source_app_slug'])
            if source != (manifest.GITHUB_ACTIONS_APP_ID, manifest.GITHUB_ACTIONS_APP_SLUG):
                errors.append(f"{manifest.SETTINGS_FILE}: required check '{context}' must come from github-actions")
            elif context not in checks and not (code_scanning and manifest.codeql_language(context)):
                errors.append(f"{manifest.SETTINGS_FILE}: required check '{context}' in ruleset "
                              f"'{ruleset['name']}' is not a pull request job without path filters "
                              'or a CodeQL default setup check')
    declared = set(data['surface']['environments'])
    for environment in sorted(set().union(*(w.environments() for w in workflows)) - declared):
        errors.append(f"{manifest.SETTINGS_FILE}: workflow environment '{environment}' "
                      'is not declared in surface/environments')
    for policy in data['environment_policies']:
        if policy['name'] not in declared:
            errors.append(f"{manifest.SETTINGS_FILE}: environment policy '{policy['name']}' "
                          'is not declared in surface/environments')
    return errors


def verify_repository(root):
    """Return every policy error for a repository root; an empty list means it passes."""
    errors, workflows = verify_actions(root)
    return errors + verify_settings(root, workflows)


def main():
    errors = verify_repository(ROOT)
    for error in errors:
        print(f'error: {error}', file=sys.stderr)
    if errors:
        return 1
    print('GitHub Actions pins and the desired settings manifest are consistent.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
