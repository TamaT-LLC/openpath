#!/usr/bin/env python3
"""Closed-schema validation of .github/settings-desired-v1.json.

The manifest uses the github-settings-desired-v1 fields of TamaT-LLC/depgraph-cli
(schemas/github-settings-desired-v1.schema.json) with two openpath-specific
relaxations:

- `required_checks[].context` accepts printable text, because openpath's check
  names (`swift build / swift test`, `Analyze (actions)`) contain spaces,
  slashes, and parentheses;
- `environment_policies[].reviewers` may be empty, because openpath restricts
  its environments (`release` and `homebrew-tap`) to release tags and `main` by
  deployment ref policy instead of required reviewers. An environment without
  reviewers must still restrict its deployment refs, so it cannot be open to
  every branch.
"""
from __future__ import annotations

import json
import pathlib
import re

SETTINGS_FILE = '.github/settings-desired-v1.json'
SCHEMA_VERSION = 'github-settings-desired-v1'
REPOSITORY = 'TamaT-LLC/openpath'
DEFAULT_BRANCH = 'main'
GITHUB_ACTIONS_APP_ID = 15368
GITHUB_ACTIONS_APP_SLUG = 'github-actions'

TOKEN = re.compile(r'[A-Za-z0-9._:+*-]{1,128}\Z')
CHECK_CONTEXT = re.compile(r'[^\x00-\x1f\x7f]{1,128}\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
BYPASS_IDENTITY = re.compile(r'(?:user|app|team|role):[A-Za-z0-9._-]{1,128}\Z')
BYPASS_MODES = ('always', 'pull_request')
# CodeQL default setup reports one `Analyze (<language>)` check per analyzed language.
CODEQL_CHECK = re.compile(r'Analyze \((?P<language>[a-z-]+)\)\Z')
CODEQL_LANGUAGES = ('actions', 'c-cpp', 'csharp', 'go', 'java-kotlin', 'javascript-typescript',
                    'python', 'ruby', 'rust', 'swift')
MAX_ITEMS = 64
MAX_INVENTORY = 256
MAX_ENVIRONMENTS = 128
MAX_APPROVALS = 6
MAX_REVIEWERS = 6
MAX_REF_PATTERN = 256

TOP_KEYS = ('schema_version', 'repository', 'default_branch', 'rulesets',
            'environment_policies', 'surface', 'security')
RULESET_KEYS = ('name', 'target', 'enforcement', 'include', 'required_checks',
                'required_approvals', 'require_code_owner_review',
                'require_conversation_resolution', 'allow_force_pushes',
                'allow_deletions', 'bypass_actors')
CHECK_KEYS = ('context', 'source_app_id', 'source_app_slug')
PRINCIPAL_KEYS = ('identity', 'permission')
ENVIRONMENT_KEYS = ('name', 'prevent_self_review', 'reviewers', 'deployment_ref_policy')
REF_POLICY_KEYS = ('protected_branches', 'custom_branch_policies', 'custom_policies')
CUSTOM_POLICY_KEYS = ('name', 'type')
SURFACE_KEYS = ('apps', 'webhook_digests', 'deploy_key_fingerprints', 'token_fingerprints',
                'teams', 'environments', 'runner_groups')
SECURITY_KEYS = ('private_vulnerability_reporting', 'security_advisories', 'secret_scanning',
                 'push_protection', 'dependency_graph', 'dependabot_alerts',
                 'dependabot_security_updates', 'code_scanning')


class _Validator:
    def __init__(self):
        self.errors = []

    def fail(self, path, message):
        self.errors.append(f'{SETTINGS_FILE}: {path}: {message}')

    def mapping(self, value, path, keys):
        if not isinstance(value, dict):
            self.fail(path, 'must be an object')
            return False
        if set(value) != set(keys):
            unknown = sorted(set(value) - set(keys))
            missing = sorted(set(keys) - set(value))
            self.fail(path, f'unknown keys {unknown}, missing keys {missing}')
            return False
        return True

    def boolean(self, value, path):
        if type(value) is not bool:
            self.fail(path, 'must be a boolean')

    def integer(self, value, path, minimum, maximum=None):
        if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
            self.fail(path, f'must be an integer in [{minimum}, {maximum}]')

    def text(self, value, path, pattern=None, max_length=None):
        valid = isinstance(value, str) and value != ''
        if valid and pattern is not None:
            valid = pattern.match(value) is not None
        if valid and max_length is not None:
            valid = len(value) <= max_length
        if not valid:
            self.fail(path, 'is not a valid string')

    def const(self, value, path, expected):
        if value != expected:
            self.fail(path, f'must be {expected!r}')

    def choice(self, value, path, options):
        if value not in options:
            self.fail(path, f'must be one of {list(options)}')

    def array(self, value, path, minimum, maximum):
        if not isinstance(value, list) or not minimum <= len(value) <= maximum:
            self.fail(path, f'must be an array with {minimum} to {maximum} items')
            return []
        return value


def _principal(check, value, path):
    if check.mapping(value, path, PRINCIPAL_KEYS):
        check.text(value['identity'], path + '/identity', TOKEN)
        check.text(value['permission'], path + '/permission', TOKEN)


def _bypass_actor(check, value, path):
    if check.mapping(value, path, PRINCIPAL_KEYS):
        check.text(value['identity'], path + '/identity', BYPASS_IDENTITY)
        check.choice(value['permission'], path + '/permission', BYPASS_MODES)


def _required_check(check, value, path):
    if check.mapping(value, path, CHECK_KEYS):
        context = value['context']
        check.text(context, path + '/context', CHECK_CONTEXT)
        if isinstance(context, str) and context != context.strip():
            check.fail(path + '/context', 'must not start or end with whitespace')
        check.integer(value['source_app_id'], path + '/source_app_id', 1)
        check.text(value['source_app_slug'], path + '/source_app_slug', TOKEN)


def _ruleset(check, value, path):
    if not check.mapping(value, path, RULESET_KEYS):
        return
    check.text(value['name'], path + '/name', TOKEN)
    check.choice(value['target'], path + '/target', ('branch', 'tag'))
    check.choice(value['enforcement'], path + '/enforcement', ('enabled', 'disabled'))
    for index, pattern in enumerate(check.array(value['include'], path + '/include', 1, MAX_ITEMS)):
        check.text(pattern, f'{path}/include/{index}', max_length=MAX_REF_PATTERN)
    checks = check.array(value['required_checks'], path + '/required_checks', 0, MAX_ITEMS)
    for index, item in enumerate(checks):
        _required_check(check, item, f'{path}/required_checks/{index}')
    contexts = [item.get('context') for item in checks if isinstance(item, dict)]
    if len(contexts) != len(set(contexts)):
        check.fail(path + '/required_checks', 'contains a duplicate context')
    check.integer(value['required_approvals'], path + '/required_approvals', 0, MAX_APPROVALS)
    for key in ('require_code_owner_review', 'require_conversation_resolution',
                'allow_force_pushes', 'allow_deletions'):
        check.boolean(value[key], f'{path}/{key}')
    for index, actor in enumerate(check.array(value['bypass_actors'], path + '/bypass_actors', 0, MAX_ITEMS)):
        _bypass_actor(check, actor, f'{path}/bypass_actors/{index}')
    reviews = (value['required_checks'], value['required_approvals'],
               value['require_code_owner_review'], value['require_conversation_resolution'])
    if value['target'] == 'tag' and reviews != ([], 0, False, False):
        check.fail(path, f"tag ruleset '{value['name']}' cannot require checks or reviews")


def _environment_policy(check, value, path):
    if not check.mapping(value, path, ENVIRONMENT_KEYS):
        return
    check.text(value['name'], path + '/name', TOKEN)
    check.boolean(value['prevent_self_review'], path + '/prevent_self_review')
    reviewers = check.array(value['reviewers'], path + '/reviewers', 0, MAX_REVIEWERS)
    for index, reviewer in enumerate(reviewers):
        check.text(reviewer, f'{path}/reviewers/{index}', TOKEN)
    ref_policy = value['deployment_ref_policy']
    ref_path = path + '/deployment_ref_policy'
    if not check.mapping(ref_policy, ref_path, REF_POLICY_KEYS):
        return
    check.boolean(ref_policy['protected_branches'], ref_path + '/protected_branches')
    check.boolean(ref_policy['custom_branch_policies'], ref_path + '/custom_branch_policies')
    policies = check.array(ref_policy['custom_policies'], ref_path + '/custom_policies', 0, MAX_ENVIRONMENTS)
    for index, item in enumerate(policies):
        item_path = f'{ref_path}/custom_policies/{index}'
        if check.mapping(item, item_path, CUSTOM_POLICY_KEYS):
            check.text(item['name'], item_path + '/name', max_length=MAX_REF_PATTERN)
            check.choice(item['type'], item_path + '/type', ('branch', 'tag'))
    # GitHub accepts only one of the two ref policies, and custom policies apply only to the custom one.
    if ref_policy['protected_branches'] is True and ref_policy['custom_branch_policies'] is True:
        check.fail(ref_path, 'protected_branches and custom_branch_policies cannot both be true')
    if ref_policy['custom_branch_policies'] is not True and policies:
        check.fail(ref_path + '/custom_policies', 'requires custom_branch_policies')
    # Without reviewers, the ref policy is the only gate in front of the environment's secrets.
    restricted = ref_policy['protected_branches'] is True or (
        ref_policy['custom_branch_policies'] is True and len(policies) > 0)
    if not reviewers and not restricted:
        check.fail(ref_path, f"environment '{value['name']}' has no reviewers and must restrict its deployment refs")


def _surface(check, value):
    if not check.mapping(value, 'surface', SURFACE_KEYS):
        return
    for key in ('apps', 'teams'):
        for index, item in enumerate(check.array(value[key], 'surface/' + key, 0, MAX_INVENTORY)):
            _principal(check, item, f'surface/{key}/{index}')
    for key in ('webhook_digests', 'deploy_key_fingerprints', 'token_fingerprints'):
        for index, item in enumerate(check.array(value[key], 'surface/' + key, 0, MAX_INVENTORY)):
            check.text(item, f'surface/{key}/{index}', DIGEST)
    for key in ('environments', 'runner_groups'):
        for index, item in enumerate(check.array(value[key], 'surface/' + key, 0, MAX_ENVIRONMENTS)):
            check.text(item, f'surface/{key}/{index}', TOKEN)


def validate(data):
    """Return schema errors of a parsed settings manifest."""
    check = _Validator()
    if not check.mapping(data, '$', TOP_KEYS):
        return check.errors
    check.const(data['schema_version'], 'schema_version', SCHEMA_VERSION)
    check.const(data['repository'], 'repository', REPOSITORY)
    check.const(data['default_branch'], 'default_branch', DEFAULT_BRANCH)
    rulesets = check.array(data['rulesets'], 'rulesets', 2, MAX_ITEMS)
    for index, ruleset in enumerate(rulesets):
        _ruleset(check, ruleset, f'rulesets/{index}')
    keys = [(r.get('target'), r.get('name')) for r in rulesets if isinstance(r, dict)]
    if len(keys) != len(set(keys)):
        check.fail('rulesets', 'contains a duplicate target and name')
    policies = check.array(data['environment_policies'], 'environment_policies', 0, MAX_ENVIRONMENTS)
    for index, policy in enumerate(policies):
        _environment_policy(check, policy, f'environment_policies/{index}')
    _surface(check, data['surface'])
    if check.mapping(data['security'], 'security', SECURITY_KEYS):
        for key in SECURITY_KEYS:
            check.boolean(data['security'][key], 'security/' + key)
    return check.errors


def codeql_language(context):
    """Return the CodeQL language of an `Analyze (<language>)` check name, or None."""
    match = CODEQL_CHECK.match(context)
    if match is None or match.group('language') not in CODEQL_LANGUAGES:
        return None
    return match.group('language')


def required_codeql_languages(data):
    """Return the CodeQL languages whose default setup checks a valid manifest requires."""
    languages = set()
    for ruleset in data['rulesets']:
        for check in ruleset['required_checks']:
            language = codeql_language(check['context'])
            if language is not None:
                languages.add(language)
    return sorted(languages)


def load(root):
    """Return (manifest, errors) for the manifest under a repository root."""
    path = pathlib.Path(root) / SETTINGS_FILE
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        return None, [f'{SETTINGS_FILE}: cannot be read as JSON: {error}']
    errors = validate(data)
    return (None if errors else data), errors
