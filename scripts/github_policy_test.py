#!/usr/bin/env python3
"""Tests for the Actions pin policy, the settings manifest, and the drift report."""
import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = pathlib.Path(__file__).resolve().parent
SHA_A = 'a' * 40
SHA_B = 'b' * 40


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {name} from {SCRIPTS}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load('github_policy_check')
drift = load('github_settings_drift')

POLICY = {
    'schema_version': 'github-actions-policy-v1',
    'actions': [
        {'identity': 'actions/cache', 'sha': SHA_B, 'reviewed_upstream_ref': 'v6'},
        {'identity': 'actions/checkout', 'sha': SHA_A, 'reviewed_upstream_ref': 'v7'},
    ],
}

CI = f'''name: CI

on:
  push:
    branches:
      - main
  pull_request:

permissions:
  contents: read

jobs:
  build:
    name: swift build / swift test
    runs-on: macos-15
    steps:
      - uses: actions/checkout@{SHA_A} # v7.0.1
        with:
          persist-credentials: false
      - name: Cache
        uses: actions/cache@{SHA_B} # v6.1.0
        with:
          path: .build
      - run: swift build
  policy:
    runs-on: ubuntu-24.04
    steps:
      - run: python3 scripts/github_policy_check.py
'''

RELEASE = f'''name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: read

jobs:
  publish:
    runs-on: ubuntu-24.04
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@{SHA_A} # v7.0.1
        with:
          persist-credentials: false
      - run: echo "${{{{ secrets.TOKEN }}}}"
'''

CHECKS = [
    {'context': 'Analyze (actions)', 'source_app_id': 15368, 'source_app_slug': 'github-actions'},
    {'context': 'policy', 'source_app_id': 15368, 'source_app_slug': 'github-actions'},
    {'context': 'swift build / swift test', 'source_app_id': 15368, 'source_app_slug': 'github-actions'},
]

SETTINGS = {
    'schema_version': 'github-settings-desired-v1',
    'repository': 'TamaT-LLC/openpath',
    'default_branch': 'main',
    'rulesets': [
        {
            'name': 'protect-main', 'target': 'branch', 'enforcement': 'enabled',
            'include': ['refs/heads/main'], 'required_checks': CHECKS,
            'required_approvals': 0, 'require_code_owner_review': False,
            'require_conversation_resolution': True, 'allow_force_pushes': False,
            'allow_deletions': False, 'bypass_actors': [],
        },
        {
            'name': 'require-code-owner-review', 'target': 'branch', 'enforcement': 'enabled',
            'include': ['refs/heads/main'], 'required_checks': [],
            'required_approvals': 1, 'require_code_owner_review': True,
            'require_conversation_resolution': False, 'allow_force_pushes': False,
            'allow_deletions': False,
            'bypass_actors': [{'identity': 'user:TakehiroT', 'permission': 'pull_request'}],
        },
        {
            'name': 'protect-release-tags', 'target': 'tag', 'enforcement': 'enabled',
            'include': ['refs/tags/v*'], 'required_checks': [], 'required_approvals': 0,
            'require_code_owner_review': False, 'require_conversation_resolution': False,
            'allow_force_pushes': False, 'allow_deletions': False, 'bypass_actors': [],
        },
    ],
    'environment_policies': [],
    'surface': {
        'apps': [{'identity': 'app:github-actions', 'permission': 'read'}],
        'webhook_digests': [], 'deploy_key_fingerprints': [], 'token_fingerprints': [],
        'teams': [], 'environments': [], 'runner_groups': ['github-hosted'],
    },
    'security': {
        'private_vulnerability_reporting': True, 'security_advisories': True,
        'secret_scanning': True, 'push_protection': True, 'dependency_graph': True,
        'dependabot_alerts': True, 'dependabot_security_updates': False, 'code_scanning': True,
    },
}


class RepositoryFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='oss-setup-policy-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / '.github/workflows').mkdir(parents=True)
        self.write_policy(POLICY)
        self.write_settings(SETTINGS)
        self.write_workflow('ci.yml', CI)
        self.write_workflow('release.yml', RELEASE)

    def write_policy(self, data):
        (self.root / '.github/actions-policy.json').write_text(json.dumps(data))

    def write_settings(self, data):
        (self.root / '.github/settings-desired-v1.json').write_text(json.dumps(data))

    def write_workflow(self, name, text):
        (self.root / '.github/workflows' / name).write_text(text)

    def errors(self):
        return check.verify_repository(self.root)

    def assert_rejected(self, fragment):
        errors = self.errors()
        self.assertTrue(any(fragment in error for error in errors), errors)


class RealRepositoryTests(unittest.TestCase):
    def test_checked_in_policy_settings_and_workflows_pass(self):
        self.assertEqual(check.verify_repository(SCRIPTS.parent), [])


class ActionsPolicyTests(RepositoryFixture):
    def test_fixture_passes(self):
        self.assertEqual(self.errors(), [])

    def test_policy_must_be_canonical(self):
        cases = {
            'unsorted': {**POLICY, 'actions': list(reversed(POLICY['actions']))},
            'mutable ref': {**POLICY, 'actions': [{**POLICY['actions'][0], 'reviewed_upstream_ref': 'v6.1.0'}, POLICY['actions'][1]]},
            'short sha': {**POLICY, 'actions': [{**POLICY['actions'][0], 'sha': 'b' * 39}, POLICY['actions'][1]]},
            'upper sha': {**POLICY, 'actions': [{**POLICY['actions'][0], 'sha': 'B' * 40}, POLICY['actions'][1]]},
            'unknown key': {**POLICY, 'note': 'x'},
            'schema': {**POLICY, 'schema_version': 'github-actions-policy-v2'},
            'subpath identity': {**POLICY, 'actions': [{**POLICY['actions'][0], 'identity': 'github/codeql-action/init'}, POLICY['actions'][1]]},
        }
        for label, policy in cases.items():
            with self.subTest(label):
                self.write_policy(policy)
                self.assert_rejected('actions-policy.json')

    def test_mutable_unlisted_or_mismatched_actions_are_rejected(self):
        cases = {
            'tag': ('actions/checkout@' + SHA_A, 'actions/checkout@v7'),
            'unlisted': ('actions/cache@' + SHA_B, 'other/cache@' + SHA_B),
            'mismatch': ('actions/cache@' + SHA_B, 'actions/cache@' + 'c' * 40),
            'docker': ('actions/cache@' + SHA_B, 'docker://alpine:3'),
        }
        for label, (old, new) in cases.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', CI.replace(old, new, 1))
                self.assert_rejected('ci.yml')

    def test_version_comment_must_match_reviewed_major(self):
        for label, comment in {'missing': '', 'other major': ' # v5.0.0', 'not a version': ' # main'}.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', CI.replace(' # v6.1.0', comment))
                self.assert_rejected('version comment')

    def test_unused_policy_entry_is_rejected(self):
        policy = copy.deepcopy(POLICY)
        policy['actions'].append({'identity': 'actions/upload-artifact', 'sha': SHA_B, 'reviewed_upstream_ref': 'v7'})
        self.write_policy(policy)
        self.assert_rejected('actions/upload-artifact')

    def test_noncanonical_uses_key_is_rejected(self):
        self.write_workflow('ci.yml', CI.replace('      - run: swift build', f'      - {{ uses: actions/checkout@{SHA_A} }}'))
        self.assert_rejected('noncanonical')

    def test_forbidden_triggers_and_escapes_are_rejected(self):
        cases = {
            'pull_request_target': CI.replace('  pull_request:\n', '  pull_request_target:\n'),
            'write-all': CI.replace('permissions:\n  contents: read\n', 'permissions: write-all\n'),
            'escape': CI.replace('run: swift build', 'run: "\\x73wift build"'),
        }
        for label, text in cases.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', text)
                self.assert_rejected('ci.yml')

    def test_top_level_permissions_must_be_read_only(self):
        cases = {
            'missing': CI.replace('permissions:\n  contents: read\n\n', ''),
            'write': CI.replace('permissions:\n  contents: read\n', 'permissions:\n  contents: write\n'),
            'extra': CI.replace('permissions:\n  contents: read\n', 'permissions:\n  contents: read\n  actions: read\n'),
        }
        for label, text in cases.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', text)
                self.assert_rejected('top-level permissions')

    def test_pull_request_workflow_cannot_use_secrets_or_write(self):
        secrets = CI.replace('      - run: swift build', '      - run: echo "${{ secrets.TOKEN }}"')
        write = CI.replace('  policy:\n    runs-on: ubuntu-24.04\n',
                           '  policy:\n    runs-on: ubuntu-24.04\n    permissions:\n      contents: write\n')
        for label, text in {'secrets': secrets, 'write': write}.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', text)
                self.assert_rejected('pull request')

    def test_tag_workflow_may_use_job_scoped_write_and_secrets(self):
        self.assertIn('${{ secrets.TOKEN }}', RELEASE)
        self.assertIn('      contents: write\n', RELEASE)
        self.assertEqual(self.errors(), [])

    def test_checkout_must_not_persist_credentials(self):
        self.write_workflow('release.yml', RELEASE.replace('        with:\n          persist-credentials: false\n', ''))
        self.assert_rejected('persist-credentials')


class SettingsManifestTests(RepositoryFixture):
    def test_closed_schema(self):
        cases = {
            'unknown top key': {**SETTINGS, 'extra': True},
            'repository': {**SETTINGS, 'repository': 'TamaT-LLC/depgraph-cli'},
            'bool as int': {**SETTINGS, 'security': {**SETTINGS['security'], 'code_scanning': 1}},
            'int as bool': {**SETTINGS, 'rulesets': [{**SETTINGS['rulesets'][0], 'required_approvals': True}, *SETTINGS['rulesets'][1:]]},
            'unknown ruleset key': {**SETTINGS, 'rulesets': [{**SETTINGS['rulesets'][0], 'strict': True}, *SETTINGS['rulesets'][1:]]},
            'duplicate ruleset': {**SETTINGS, 'rulesets': [*SETTINGS['rulesets'], SETTINGS['rulesets'][0]]},
            'bypass mode': {**SETTINGS, 'rulesets': [SETTINGS['rulesets'][0], {**SETTINGS['rulesets'][1], 'bypass_actors': [{'identity': 'user:TakehiroT', 'permission': 'admin'}]}, SETTINGS['rulesets'][2]]},
            'digest': {**SETTINGS, 'surface': {**SETTINGS['surface'], 'webhook_digests': ['abc']}},
        }
        for label, settings in cases.items():
            with self.subTest(label):
                self.write_settings(settings)
                self.assert_rejected('settings-desired-v1.json')

    def test_required_checks_must_come_from_pull_request_jobs(self):
        settings = copy.deepcopy(SETTINGS)
        settings['rulesets'][0]['required_checks'].append(
            {'context': 'publish', 'source_app_id': 15368, 'source_app_slug': 'github-actions'})
        self.write_settings(settings)
        self.assert_rejected("'publish'")

    def test_codeql_checks_require_code_scanning(self):
        settings = copy.deepcopy(SETTINGS)
        settings['security']['code_scanning'] = False
        self.write_settings(settings)
        self.assert_rejected("'Analyze (actions)'")

    def test_codeql_checks_must_name_a_codeql_language(self):
        settings = copy.deepcopy(SETTINGS)
        settings['rulesets'][0]['required_checks'][0]['context'] = 'Analyze (pyhton)'
        self.write_settings(settings)
        self.assert_rejected("'Analyze (pyhton)'")

    def test_path_filtered_pull_request_cannot_provide_required_checks(self):
        self.write_workflow('ci.yml', CI.replace('  pull_request:\n', '  pull_request:\n    paths:\n      - Sources/**\n'))
        self.assert_rejected("'swift build / swift test'")

    def test_required_check_jobs_cannot_be_conditional(self):
        # A job skipped by its `if:` reports success, so it would satisfy the required check.
        self.write_workflow('ci.yml', CI.replace('    runs-on: macos-15\n', '    if: false\n    runs-on: macos-15\n'))
        self.assert_rejected("'swift build / swift test'")
        self.write_workflow('ci.yml', CI.replace('    runs-on: ubuntu-24.04\n', "    if: github.actor != 'x'\n    runs-on: ubuntu-24.04\n"))
        self.assert_rejected("'policy'")
        for key in ('"if"', "'if'", 'if '):
            with self.subTest(key):
                self.write_workflow('ci.yml', CI.replace('    runs-on: macos-15\n', f'    {key}: false\n    runs-on: macos-15\n'))
                self.assert_rejected("'swift build / swift test'")

    def test_quoted_trigger_filters_are_detected(self):
        for key in ('"paths"', "'paths-ignore'"):
            with self.subTest(key):
                self.write_workflow('ci.yml', CI.replace('  pull_request:\n', f'  pull_request:\n    {key}:\n      - Sources/**\n'))
                self.assert_rejected("'swift build / swift test'")

    def test_flow_style_mapping_in_triggers_is_rejected(self):
        cases = {
            'flow mapping': CI.replace('  pull_request:\n', "  pull_request: {paths: ['Sources/**']}\n"),
            'deeper indentation': CI.replace('  pull_request:\n', '  pull_request:\n      paths:\n        - Sources/**\n'),
        }
        for label, text in cases.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', text)
                self.assert_rejected('block style')

    def test_flow_style_sequence_in_pull_request_job_is_rejected(self):
        cases = {
            'flow sequence': CI.replace('    runs-on: macos-15\n', '    needs: [policy]\n    runs-on: macos-15\n'),
            'alias': CI.replace('    runs-on: macos-15\n', '    <<: *defaults\n    runs-on: macos-15\n'),
        }
        for label, text in cases.items():
            with self.subTest(label):
                self.write_workflow('ci.yml', text)
                self.assert_rejected('block style')

    def test_explicit_yaml_keys_are_rejected(self):
        self.write_workflow('ci.yml', CI.replace('    runs-on: macos-15\n', '    ? if\n    : false\n    runs-on: macos-15\n'))
        self.assert_rejected('explicit YAML keys')

    def test_tag_ruleset_cannot_require_reviews_or_checks(self):
        settings = copy.deepcopy(SETTINGS)
        settings['rulesets'][2]['required_approvals'] = 1
        self.write_settings(settings)
        self.assert_rejected('protect-release-tags')

    def test_environment_without_reviewers_must_restrict_deployment_refs(self):
        tag_only = {'protected_branches': False, 'custom_branch_policies': True,
                    'custom_policies': [{'name': 'v*', 'type': 'tag'}]}
        policy = {'name': 'release', 'prevent_self_review': False, 'reviewers': [],
                  'deployment_ref_policy': tag_only}
        settings = copy.deepcopy(SETTINGS)
        settings['surface']['environments'] = ['release']
        settings['environment_policies'] = [policy]
        self.write_settings(settings)
        self.assertEqual(self.errors(), [])
        open_refs = {
            'all branches': {'protected_branches': False, 'custom_branch_policies': False, 'custom_policies': []},
            'no custom policy': {'protected_branches': False, 'custom_branch_policies': True, 'custom_policies': []},
            'policies without custom': {**tag_only, 'custom_branch_policies': False},
            'both ref policies': {**tag_only, 'protected_branches': True},
        }
        for label, ref_policy in open_refs.items():
            with self.subTest(label):
                settings['environment_policies'] = [{**policy, 'deployment_ref_policy': ref_policy}]
                self.write_settings(settings)
                self.assert_rejected('deployment_ref_policy')
        settings['environment_policies'] = [{**policy, 'reviewers': ['user:TakehiroT'],
                                             'deployment_ref_policy': open_refs['all branches']}]
        self.write_settings(settings)
        self.assertEqual(self.errors(), [])

    def test_allow_creations_is_an_optional_boolean_of_tag_rulesets(self):
        settings = copy.deepcopy(SETTINGS)
        settings['rulesets'][2]['allow_creations'] = False
        self.write_settings(settings)
        self.assertEqual(self.errors(), [])
        cases = {
            'not a boolean': (2, 0),
            'branch ruleset': (0, False),
        }
        for label, (index, value) in cases.items():
            with self.subTest(label):
                settings = copy.deepcopy(SETTINGS)
                settings['rulesets'][index]['allow_creations'] = value
                self.write_settings(settings)
                self.assert_rejected('allow_creations')

    def test_workflow_environments_must_be_declared(self):
        self.write_workflow('release.yml', RELEASE.replace('    runs-on: ubuntu-24.04\n', '    runs-on: ubuntu-24.04\n    environment: release\n'))
        self.assert_rejected("'release'")
        settings = copy.deepcopy(SETTINGS)
        settings['surface']['environments'] = ['release']
        self.write_settings(settings)
        self.assertEqual(self.errors(), [])


def live_ruleset(identifier, name, target, include, rules, bypass=()):
    return {'id': identifier, 'name': name, 'target': target, 'enforcement': 'active',
            'conditions': {'ref_name': {'include': include, 'exclude': []}},
            'rules': rules, 'bypass_actors': list(bypass)}


def pull_request_rule(approvals=0, code_owner=False, threads=False, stale=False, last_push=False):
    return {'type': 'pull_request', 'parameters': {
        'required_approving_review_count': approvals, 'require_code_owner_review': code_owner,
        'required_review_thread_resolution': threads, 'dismiss_stale_reviews_on_push': stale,
        'require_last_push_approval': last_push}}


def matching_live_state():
    checks = [{'context': c['context'], 'integration_id': 15368} for c in CHECKS]
    rulesets = [
        live_ruleset(1, 'protect-main', 'branch', ['refs/heads/main'], [
            {'type': 'deletion'}, {'type': 'non_fast_forward'}, pull_request_rule(threads=True),
            {'type': 'required_status_checks', 'parameters': {
                'required_status_checks': checks, 'strict_required_status_checks_policy': True}}]),
        live_ruleset(2, 'require-code-owner-review', 'branch', ['refs/heads/main'], [
            pull_request_rule(approvals=1, code_owner=True, stale=True, last_push=True)],
            bypass=[{'actor_id': 33048137, 'actor_type': 'User', 'bypass_mode': 'pull_request'}]),
        live_ruleset(3, 'protect-release-tags', 'tag', ['refs/tags/v*'], [{'type': 'update'}, {'type': 'deletion'}]),
    ]
    responses = {
        'repos/TamaT-LLC/openpath': {'default_branch': 'main', 'visibility': 'public', 'security_and_analysis': {
            'secret_scanning': {'status': 'enabled'}, 'secret_scanning_push_protection': {'status': 'enabled'},
            'dependabot_security_updates': {'status': 'disabled'}}},
        'repos/TamaT-LLC/openpath/rulesets?per_page=100': [{'id': r['id']} for r in rulesets],
        'repos/TamaT-LLC/openpath/environments?per_page=100': {'environments': []},
        'repos/TamaT-LLC/openpath/hooks?per_page=100': [],
        'repos/TamaT-LLC/openpath/keys?per_page=100': [],
        'repos/TamaT-LLC/openpath/teams?per_page=100': [],
        'repos/TamaT-LLC/openpath/private-vulnerability-reporting': {'enabled': True},
        'repos/TamaT-LLC/openpath/vulnerability-alerts': None,
        'repos/TamaT-LLC/openpath/code-scanning/default-setup': {'state': 'configured', 'languages': ['actions', 'python']},
        'user/33048137': {'login': 'TakehiroT'},
    }
    for ruleset in rulesets:
        responses[f"repos/TamaT-LLC/openpath/rulesets/{ruleset['id']}"] = ruleset
    return responses


class DriftTests(unittest.TestCase):
    def report(self, responses, settings=SETTINGS):
        def fetch(path):
            value = responses[path]
            if isinstance(value, drift.ApiError):
                raise value
            return copy.deepcopy(value)
        return drift.drift_report(settings, fetch)

    def test_matching_live_state_has_no_drift(self):
        self.assertEqual(self.report(matching_live_state()), [])

    def test_current_openpath_state_lists_every_missing_setting(self):
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/rulesets?per_page=100'] = []
        responses['repos/TamaT-LLC/openpath']['security_and_analysis'] = {
            'secret_scanning': {'status': 'disabled'}, 'secret_scanning_push_protection': {'status': 'disabled'},
            'dependabot_security_updates': {'status': 'disabled'}}
        responses['repos/TamaT-LLC/openpath/private-vulnerability-reporting'] = {'enabled': False}
        responses['repos/TamaT-LLC/openpath/code-scanning/default-setup'] = {'state': 'not-configured'}
        report = '\n'.join(self.report(responses))
        for expected in ['rulesets/branch/protect-main: missing', 'rulesets/branch/require-code-owner-review: missing',
                         'rulesets/tag/protect-release-tags: missing', 'security/private_vulnerability_reporting',
                         'security/secret_scanning:', 'security/push_protection', 'security/code_scanning']:
            self.assertIn(expected, report)

    def test_implied_strict_last_push_and_stale_dismissal_are_verified(self):
        responses = matching_live_state()
        main = responses['repos/TamaT-LLC/openpath/rulesets/1']
        main['rules'][3]['parameters']['strict_required_status_checks_policy'] = False
        owner = responses['repos/TamaT-LLC/openpath/rulesets/2']
        owner['rules'][0]['parameters']['require_last_push_approval'] = False
        owner['rules'][0]['parameters']['dismiss_stale_reviews_on_push'] = False
        report = '\n'.join(self.report(responses))
        self.assertIn('protect-main/strict_required_status_checks', report)
        self.assertIn('require-code-owner-review/require_last_push_approval', report)
        self.assertIn('require-code-owner-review/dismiss_stale_reviews_on_push', report)

    def test_history_protection_is_evaluated_across_rulesets_for_the_same_refs(self):
        responses = matching_live_state()
        main = responses['repos/TamaT-LLC/openpath/rulesets/1']
        main['rules'] = [rule for rule in main['rules'] if rule['type'] != 'deletion']
        report = self.report(responses)
        self.assertIn('rulesets/branch/protect-main/allow_deletions: expected false, actual true', report)
        self.assertIn('rulesets/branch/require-code-owner-review/allow_deletions: expected false, actual true', report)
        self.assertNotIn('rulesets/branch/require-code-owner-review/allow_force_pushes: expected false, actual true', report)

    def test_unexpected_rules_rulesets_and_bypass_are_reported(self):
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/rulesets/2']['bypass_actors'].append(
            {'actor_id': 2740, 'actor_type': 'Integration', 'bypass_mode': 'always'})
        responses['repos/TamaT-LLC/openpath/rulesets/3']['rules'].append({'type': 'required_signatures'})
        responses['repos/TamaT-LLC/openpath/rulesets?per_page=100'].append({'id': 4})
        responses['repos/TamaT-LLC/openpath/rulesets/4'] = live_ruleset(4, 'legacy', 'branch', ['~ALL'], [])
        report = '\n'.join(self.report(responses))
        self.assertIn('require-code-owner-review/bypass_actors', report)
        self.assertIn('app:renovate', report)
        self.assertIn('protect-release-tags/rules: unexpected required_signatures', report)
        self.assertIn('rulesets/branch/legacy: unexpected', report)

    def test_environment_reviewers_and_deployment_refs_are_compared(self):
        settings = copy.deepcopy(SETTINGS)
        settings['surface']['environments'] = ['release']
        settings['environment_policies'] = [{
            'name': 'release', 'prevent_self_review': False, 'reviewers': [],
            'deployment_ref_policy': {'protected_branches': False, 'custom_branch_policies': True,
                                      'custom_policies': [{'name': 'v*', 'type': 'tag'}]}}]
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/environments?per_page=100'] = {'environments': [{
            'name': 'release', 'protection_rules': [{'type': 'branch_policy'}],
            'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True}}]}
        branch_policies = 'repos/TamaT-LLC/openpath/environments/release/deployment-branch-policies?per_page=100'
        responses[branch_policies] = {'branch_policies': [{'name': 'v*', 'type': 'tag'}]}
        self.assertEqual(self.report(responses, settings), [])
        responses[branch_policies] = {'branch_policies': [{'name': 'v*', 'type': 'tag'}, {'name': '*', 'type': 'branch'}]}
        self.assertIn('environment_policies/release/deployment_ref_policy', '\n'.join(self.report(responses, settings)))
        responses['repos/TamaT-LLC/openpath/environments?per_page=100'] = {'environments': []}
        report = self.report(responses, settings)
        self.assertIn('surface/environments: expected ["release"], actual []', report)
        self.assertIn('environment_policies/release: missing', report)

    def test_tag_creation_rule_and_repository_admin_bypass_are_compared(self):
        settings = copy.deepcopy(SETTINGS)
        settings['rulesets'][2]['allow_creations'] = False
        settings['rulesets'][2]['bypass_actors'] = [{'identity': 'role:repository-admin', 'permission': 'always'}]
        responses = matching_live_state()
        tags = responses['repos/TamaT-LLC/openpath/rulesets/3']
        tags['rules'].append({'type': 'creation'})
        tags['bypass_actors'] = [{'actor_id': 5, 'actor_type': 'RepositoryRole', 'bypass_mode': 'always'}]
        self.assertEqual(self.report(responses, settings), [])
        tags['rules'] = [rule for rule in tags['rules'] if rule['type'] != 'creation']
        tags['bypass_actors'] = [{'actor_id': 4, 'actor_type': 'RepositoryRole', 'bypass_mode': 'always'}]
        report = '\n'.join(self.report(responses, settings))
        self.assertIn('protect-release-tags/allow_creations: expected false, actual true', report)
        self.assertIn('role:repository-role-4', report)
        # allow_creations を書かない tag ruleset は作成を許す（creation rule があれば差分）
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/rulesets/3']['rules'].append({'type': 'creation'})
        self.assertEqual(self.report(responses),
                         ['rulesets/tag/protect-release-tags/allow_creations: expected true, actual false'])

    def test_codeql_default_setup_must_analyze_every_required_language(self):
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/code-scanning/default-setup'] = {'state': 'configured', 'languages': ['python']}
        self.assertIn('security/code_scanning/languages: expected to include ["actions"], actual ["python"]',
                      self.report(responses))

    def test_disabled_dependabot_alerts_are_reported(self):
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/vulnerability-alerts'] = drift.ApiError('vulnerability-alerts', 404, 'Not Found')
        self.assertIn('security/dependabot_alerts: expected true, actual false', self.report(responses))

    def test_gh_fetch_turns_empty_or_invalid_bodies_into_api_errors(self):
        def completed(stdout):
            return drift.subprocess.CompletedProcess(['gh'], 0, stdout=stdout, stderr='')

        cases = {
            ('repos/o/r/vulnerability-alerts', ''): None,
            ('repos/o/r/hooks?per_page=100', '[]\n'): [],
            ('repos/o/r', '{"default_branch": "main"}'): {'default_branch': 'main'},
        }
        for (path, stdout), expected in cases.items():
            with self.subTest(path), patch.object(drift.subprocess, 'run', return_value=completed(stdout)):
                self.assertEqual(drift.gh_fetch(path), expected)
        for path, stdout in {'repos/o/r': '', 'repos/o/r/rulesets?per_page=100': '<html>'}.items():
            with self.subTest(path), patch.object(drift.subprocess, 'run', return_value=completed(stdout)):
                with self.assertRaises(drift.ApiError):
                    drift.gh_fetch(path)

    def test_permission_failure_stops_the_report(self):
        responses = matching_live_state()
        responses['repos/TamaT-LLC/openpath/hooks?per_page=100'] = drift.ApiError('hooks', 403, 'Forbidden')
        with self.assertRaises(drift.ApiError):
            self.report(responses)


if __name__ == '__main__':
    unittest.main()
