#!/usr/bin/env python3
"""List differences between .github/settings-desired-v1.json and the live settings.

Read-only: it sends only GET requests through `gh api` and never changes a
setting. Run it with an account that can read the repository's administration
and security settings:

    python3 scripts/github_settings_drift.py

Exit status: 0 = no drift, 1 = drift listed on stdout, 2 = the manifest is
invalid or the settings could not be read.

Some ruleset parameters are not fields of github-settings-desired-v1 but follow
from it, as in the live rulesets of depgraph-cli and repo-knowledge-mcp:

- a ruleset with required checks requires branches to be up to date (strict);
- a ruleset that requires code owner review also dismisses stale approvals and
  requires approval of the most recent push;
- allow_force_pushes = false means an active ruleset for the same refs has a
  non_fast_forward rule (branches) or an update rule (tags), and
  allow_deletions = false means one has a deletion rule; as in depgraph-cli,
  require-code-owner-review relies on protect-main for this protection;
- a branch ruleset with approvals, code owner review, or conversation
  resolution has a pull_request rule;
- every required `Analyze (<language>)` check needs CodeQL default setup to
  analyze that language.

security_advisories and dependency_graph are always on for public repositories,
so they are read from the visibility. Apps, token fingerprints, and runner groups
need organization-level access and are not verified.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

import github_settings_manifest as manifest

ROOT = pathlib.Path(__file__).resolve().parent.parent
DESCRIPTION = 'List differences between .github/settings-desired-v1.json and the live settings.'
KNOWN_APPS = {15368: 'github-actions', 2740: 'renovate'}
ALLOWED_RULES = {
    'branch': {'deletion', 'non_fast_forward', 'pull_request', 'required_status_checks'},
    'tag': {'deletion', 'update'},
}
HISTORY_RULE = {'branch': 'non_fast_forward', 'tag': 'update'}
NOT_VERIFIED = ('surface/apps', 'surface/token_fingerprints', 'surface/runner_groups')
HTTP_STATUS = re.compile(r'HTTP (\d{3})')
EMPTY_BODY_PATH_SUFFIX = '/vulnerability-alerts'
NOT_FOUND = 404


class ApiError(Exception):
    def __init__(self, path, status, message):
        super().__init__(f'{path}: HTTP {status}: {message}')
        self.path = path
        self.status = status


def gh_fetch(path):
    """GET one REST path with the GitHub CLI.

    Only the vulnerability-alerts endpoint answers with an empty body (204) and
    returns None; an empty or non-JSON body from any other path is an ApiError.
    """
    result = subprocess.run(['gh', 'api', '--method', 'GET', path],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        status = HTTP_STATUS.search(result.stderr)
        raise ApiError(path, int(status.group(1)) if status else 0, result.stderr.strip())
    if not result.stdout.strip():
        if path.endswith(EMPTY_BODY_PATH_SUFFIX):
            return None
        raise ApiError(path, 0, 'empty response')
    try:
        return json.loads(result.stdout)
    except ValueError as error:
        raise ApiError(path, 0, f'invalid JSON: {error}') from error


def _show(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def _compare(drift, path, expected, actual):
    if expected != actual:
        drift.append(f'{path}: expected {_show(expected)}, actual {_show(actual)}')


def _actor(fetch, actor):
    kind, identifier = actor.get('actor_type'), actor.get('actor_id')
    if kind == 'User':
        return 'user:' + fetch(f'user/{identifier}')['login']
    if kind == 'Integration':
        return 'app:' + KNOWN_APPS.get(identifier, f'id-{identifier}')
    if kind == 'OrganizationAdmin':
        return 'role:organization-admin'
    return f'{str(kind).lower()}:{identifier}'


def _normalize_ruleset(fetch, live):
    target = live['target']
    rules = {rule['type']: rule.get('parameters') or {} for rule in live.get('rules', [])}
    review = rules.get('pull_request')
    status = rules.get('required_status_checks', {})
    ref_name = (live.get('conditions') or {}).get('ref_name') or {}
    checks = [{'context': c['context'], 'source_app_id': c.get('integration_id'),
               'source_app_slug': KNOWN_APPS.get(c.get('integration_id'), 'any')}
              for c in status.get('required_status_checks', [])]
    actors = [{'identity': _actor(fetch, a), 'permission': a.get('bypass_mode')}
              for a in live.get('bypass_actors') or []]
    fields = {
        'enforcement': 'enabled' if live.get('enforcement') == 'active' else 'disabled',
        'include': sorted(ref_name.get('include', [])),
        'required_checks': sorted(checks, key=lambda c: c['context']),
        'required_approvals': (review or {}).get('required_approving_review_count', 0),
        'require_code_owner_review': bool((review or {}).get('require_code_owner_review')),
        'require_conversation_resolution': bool((review or {}).get('required_review_thread_resolution')),
        'allow_force_pushes': HISTORY_RULE.get(target) not in rules,
        'allow_deletions': 'deletion' not in rules,
        'bypass_actors': sorted(actors, key=lambda a: a['identity']),
    }
    implied = {
        'pull_request_rule': review is not None,
        'strict_required_status_checks': bool(status.get('strict_required_status_checks_policy')),
        'dismiss_stale_reviews_on_push': bool((review or {}).get('dismiss_stale_reviews_on_push')),
        'require_last_push_approval': bool((review or {}).get('require_last_push_approval')),
        'exclude': ref_name.get('exclude', []),
    }
    unexpected = sorted(set(rules) - ALLOWED_RULES.get(target, set()))
    return fields, implied, unexpected


def _expected_ruleset(desired):
    fields = {key: desired[key] for key in manifest.RULESET_KEYS if key not in ('name', 'target')}
    fields['include'] = sorted(fields['include'])
    fields['required_checks'] = sorted(fields['required_checks'], key=lambda c: c['context'])
    fields['bypass_actors'] = sorted(fields['bypass_actors'], key=lambda a: a['identity'])
    code_owner = desired['require_code_owner_review']
    implied = {
        'pull_request_rule': desired['target'] == 'branch' and (
            desired['required_approvals'] > 0 or code_owner or desired['require_conversation_resolution']),
        'strict_required_status_checks': bool(desired['required_checks']),
        'dismiss_stale_reviews_on_push': code_owner,
        'require_last_push_approval': code_owner,
        'exclude': [],
    }
    return fields, implied


def _effective_rules(live):
    """Map (target, ref pattern) to the rule types of every active ruleset that includes it."""
    effective = {}
    for ruleset in live.values():
        if ruleset.get('enforcement') != 'active':
            continue
        types = {rule['type'] for rule in ruleset.get('rules', [])}
        for pattern in ((ruleset.get('conditions') or {}).get('ref_name') or {}).get('include', []):
            effective.setdefault((ruleset['target'], pattern), set()).update(types)
    return effective


def _ruleset_drift(desired, fetch, base):
    drift = []
    live = {}
    for summary in fetch(f'{base}/rulesets?per_page=100') or []:
        ruleset = fetch(f"{base}/rulesets/{summary['id']}")
        live[(ruleset['target'], ruleset['name'])] = ruleset
    effective = _effective_rules(live)
    for ruleset in desired['rulesets']:
        key = (ruleset['target'], ruleset['name'])
        path = f'rulesets/{key[0]}/{key[1]}'
        if key not in live:
            drift.append(f'{path}: missing')
            continue
        expected, expected_implied = _expected_ruleset(ruleset)
        actual, actual_implied, unexpected = _normalize_ruleset(fetch, live.pop(key))
        # History protection is cumulative: another active ruleset for the same refs may provide it.
        protected = set.intersection(*(effective.get((key[0], p), set()) for p in ruleset['include']))
        actual['allow_force_pushes'] = HISTORY_RULE[key[0]] not in protected
        actual['allow_deletions'] = 'deletion' not in protected
        for field in expected:
            _compare(drift, f'{path}/{field}', expected[field], actual[field])
        for field in expected_implied:
            _compare(drift, f'{path}/{field}', expected_implied[field], actual_implied[field])
        drift += [f'{path}/rules: unexpected {rule}' for rule in unexpected]
    drift += [f'rulesets/{target}/{name}: unexpected' for target, name in sorted(live)]
    return drift


def _environment_drift(desired, fetch, base):
    drift = []
    live = {}
    for environment in (fetch(f'{base}/environments?per_page=100') or {}).get('environments', []):
        name = environment['name']
        rules = {rule['type']: rule for rule in environment.get('protection_rules', [])}
        reviewers = rules.get('required_reviewers', {})
        branch_policy = environment.get('deployment_branch_policy')
        custom = []
        if branch_policy and branch_policy.get('custom_branch_policies'):
            policies = fetch(f'{base}/environments/{name}/deployment-branch-policies?per_page=100')
            custom = [{'name': p['name'], 'type': p.get('type', 'branch')} for p in policies['branch_policies']]
        live[name] = {
            'prevent_self_review': bool(reviewers.get('prevent_self_review')),
            'reviewers': sorted(('user:' if r['type'] == 'User' else 'team:')
                                + (r['reviewer'].get('login') or r['reviewer'].get('slug'))
                                for r in reviewers.get('reviewers', [])),
            'deployment_ref_policy': {
                'protected_branches': bool(branch_policy and branch_policy.get('protected_branches')),
                'custom_branch_policies': bool(branch_policy and branch_policy.get('custom_branch_policies')),
                'custom_policies': sorted(custom, key=lambda p: (p['type'], p['name'])),
            },
        }
    _compare(drift, 'surface/environments', sorted(desired['surface']['environments']), sorted(live))
    for policy in desired['environment_policies']:
        path = f"environment_policies/{policy['name']}"
        actual = live.get(policy['name'])
        if actual is None:
            drift.append(f'{path}: missing')
            continue
        expected = {key: policy[key] for key in ('prevent_self_review', 'deployment_ref_policy')}
        expected['reviewers'] = sorted(policy['reviewers'])
        expected['deployment_ref_policy'] = dict(expected['deployment_ref_policy'], custom_policies=sorted(
            policy['deployment_ref_policy']['custom_policies'], key=lambda p: (p['type'], p['name'])))
        for field in expected:
            _compare(drift, f'{path}/{field}', expected[field], actual[field])
    return drift


def _surface_drift(desired, fetch, base):
    drift = []
    surface = desired['surface']
    _compare(drift, 'surface/webhooks', len(surface['webhook_digests']),
             len(fetch(f'{base}/hooks?per_page=100') or []))
    _compare(drift, 'surface/deploy_keys', len(surface['deploy_key_fingerprints']),
             len(fetch(f'{base}/keys?per_page=100') or []))
    teams = [{'identity': 'team:' + t['slug'], 'permission': t.get('permission')}
             for t in fetch(f'{base}/teams?per_page=100') or []]
    _compare(drift, 'surface/teams', sorted(surface['teams'], key=lambda t: t['identity']),
             sorted(teams, key=lambda t: t['identity']))
    return drift


def _security_drift(desired, fetch, base, repository):
    analysis = repository.get('security_and_analysis')
    if analysis is None:
        raise ApiError(base, 403, 'security_and_analysis is not visible to this account')

    def enabled(key):
        return (analysis.get(key) or {}).get('status') == 'enabled'

    try:
        fetch(f'{base}/vulnerability-alerts')
        dependabot_alerts = True
    except ApiError as error:
        if error.status != NOT_FOUND:
            raise
        dependabot_alerts = False
    public = repository.get('visibility') == 'public'
    default_setup = fetch(f'{base}/code-scanning/default-setup')
    configured = default_setup.get('state') == 'configured'
    actual = {
        'private_vulnerability_reporting': bool(fetch(f'{base}/private-vulnerability-reporting').get('enabled')),
        'security_advisories': public,
        'secret_scanning': enabled('secret_scanning'),
        'push_protection': enabled('secret_scanning_push_protection'),
        'dependency_graph': public,
        'dependabot_alerts': dependabot_alerts,
        'dependabot_security_updates': enabled('dependabot_security_updates'),
        'code_scanning': configured,
    }
    drift = []
    for key in manifest.SECURITY_KEYS:
        _compare(drift, f'security/{key}', desired['security'][key], actual[key])
    # A required `Analyze (<language>)` check appears only when default setup analyzes that language.
    required = manifest.required_codeql_languages(desired)
    languages = sorted(default_setup.get('languages') or [])
    if configured and not set(required) <= set(languages):
        drift.append(f'security/code_scanning/languages: expected to include {_show(required)}, '
                     f'actual {_show(languages)}')
    return drift


def drift_report(desired, fetch):
    """Return drift lines between a valid manifest and the settings read through fetch."""
    base = f"repos/{desired['repository']}"
    repository = fetch(base)
    drift = []
    _compare(drift, 'default_branch', desired['default_branch'], repository.get('default_branch'))
    drift += _ruleset_drift(desired, fetch, base)
    drift += _environment_drift(desired, fetch, base)
    drift += _surface_drift(desired, fetch, base)
    drift += _security_drift(desired, fetch, base, repository)
    return drift


def main(argv=None):
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument('--root', type=pathlib.Path, default=ROOT, help='repository root')
    args = parser.parse_args(argv)
    desired, errors = manifest.load(args.root)
    for error in errors:
        print(f'error: {error}', file=sys.stderr)
    if desired is None:
        return 2
    try:
        drift = drift_report(desired, gh_fetch)
    except ApiError as error:
        print(f'error: could not read the live settings: {error}', file=sys.stderr)
        return 2
    print(f"{desired['repository']} compared with {manifest.SETTINGS_FILE} (read-only)")
    for line in drift:
        print(f'- {line}')
    print('not verified: ' + ', '.join(NOT_VERIFIED))
    print(f'{len(drift)} difference(s)')
    return 1 if drift else 0


if __name__ == '__main__':
    sys.exit(main())
