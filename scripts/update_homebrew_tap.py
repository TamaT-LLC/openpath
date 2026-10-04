#!/usr/bin/env python3
"""Open a pull request in the Homebrew tap with the cask of a published Stable release.

`verify` downloads the assets of the release with the repository token and checks
them against each other. `update` compares the verified cask with the tap: when the
tap is behind, it commits the cask to `openpath-vX.Y.Z` as the GitHub App bot, opens
or reuses the pull request, and requests auto-merge. With `--dry-run` it stops after
cloning the tap and showing the difference.

The tap's `release check` compares only version, sha256, and url with the release,
so the tap may fix other lines (such as `depends_on`) by hand. A cask with the same
version, sha256, and url counts as already reflected, on the default branch and on
an existing pull request branch, and those edits are kept.

Tokens never appear in arguments or output: `gh` reads GH_TOKEN, and git asks
`gh auth git-credential` for it only when the remote requires authentication.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

from publish_release import validate_assets
from release_metadata import VERSION, parse_tag

SOURCE_REPO = 'TamaT-LLC/openpath'
TAP_REPO = 'TamaT-LLC/homebrew-tap'
CASK_ASSET = 'openpath.rb'
CASK_PATH = 'Casks/' + CASK_ASSET
CASK_HEADER = 'cask "openpath" do\n'
CASK_URL = f'https://github.com/{SOURCE_REPO}/releases/download/v#{{version}}/openpath-#{{version}}.zip'
RELEASE_FIELDS = ('version', 'sha256', 'url')
APP_SLUG = re.compile(r'[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\Z')
GIT_AUTH = ('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential')
BRANCH_MISSING = 2  # exit status of `git ls-remote --exit-code` when no ref matches

UNCHANGED = 'unchanged'
NEWER = 'newer'
DRY_RUN = 'dry-run'
UPDATED = 'updated'


def gh(*args: str) -> str:
    return subprocess.check_output(['gh', *args], text=True)


def git(cwd: pathlib.Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ, GIT_TERMINAL_PROMPT='0')
    return subprocess.run(['git', *GIT_AUTH, *args], cwd=cwd, check=check, stdout=subprocess.PIPE,
                          text=True, env=environment)


def stable_version(tag: str) -> str:
    channel, version, _ = parse_tag(tag)
    if channel != 'stable':
        raise ValueError('only a Stable tag vX.Y.Z updates the Homebrew tap')
    return version


def asset_names(version: str) -> list[str]:
    return sorted([f'openpath-{version}.zip', CASK_ASSET, 'SHA256SUMS'])


def cask_field(text: str, name: str) -> str | None:
    values = re.findall(rf'^  {name} "([^"\n]*)"$', text, re.MULTILINE)
    return values[0] if len(values) == 1 else None


def release_fields(text: str) -> tuple[str | None, ...]:
    """The stanzas the tap's release check compares with the release."""
    return tuple(cask_field(text, name) for name in RELEASE_FIELDS)


def verify_assets(directory: pathlib.Path, tag: str) -> str:
    """Check SHA256SUMS, the ZIP, and the cask against the tag; return the version."""
    version = stable_version(tag)
    validate_assets(directory, 'stable', version, '')
    cask = (directory / CASK_ASSET).read_text()
    archive = hashlib.sha256((directory / f'openpath-{version}.zip').read_bytes()).hexdigest()
    if not cask.startswith(CASK_HEADER):
        raise ValueError('the cask must define cask "openpath"')
    if cask_field(cask, 'version') != version:
        raise ValueError(f'cask version must be exactly one "{version}" that matches the tag')
    if cask_field(cask, 'sha256') != archive:
        raise ValueError('cask sha256 must match the ZIP')
    if cask_field(cask, 'url') != CASK_URL:
        raise ValueError(f'cask url must be {CASK_URL}')
    return version


def fetch_release(repo: str, tag: str, directory: pathlib.Path) -> str:
    """Download the assets of a published Stable release into an empty directory and verify them."""
    version = stable_version(tag)
    release = json.loads(gh('release', 'view', tag, '--repo', repo, '--json', 'tagName,isDraft,isPrerelease,assets'))
    if release['tagName'] != tag or release['isDraft'] or release['isPrerelease']:
        raise ValueError(f'{tag} must be a published Stable release, neither a draft nor a prerelease')
    names = asset_names(version)
    if sorted(asset['name'] for asset in release['assets']) != names:
        raise ValueError('release assets are missing or unexpected assets are attached')
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        raise ValueError(f'{directory} must be empty')
    patterns = [arg for name in names for arg in ('--pattern', name)]
    gh('release', 'download', tag, '--repo', repo, '--dir', str(directory), *patterns)
    return verify_assets(directory, tag)


def is_newer(current: str | None, version: str) -> bool:
    if current is None or not re.fullmatch(VERSION, current):
        return False
    return tuple(map(int, current.split('.'))) > tuple(map(int, version.split('.')))


def check_out_branch(work: pathlib.Path, branch: str) -> None:
    """Continue an existing remote branch instead of recreating it."""
    found = git(work, 'ls-remote', '--exit-code', '--heads', 'origin', 'refs/heads/' + branch, check=False)
    if found.returncode == BRANCH_MISSING:
        git(work, 'switch', '--quiet', '-c', branch)
        return
    if found.returncode != 0:
        raise subprocess.CalledProcessError(found.returncode, ['git', 'ls-remote', 'origin', branch])
    git(work, 'fetch', '--quiet', 'origin', f'+refs/heads/{branch}:refs/remotes/origin/{branch}')
    git(work, 'switch', '--quiet', '-c', branch, 'origin/' + branch)
    print(f'Continuing the existing branch {branch}.')


def bot_identity(app_slug: str) -> tuple[str, str]:
    user_id = gh('api', f'users/{app_slug}[bot]', '--jq', '.id').strip()
    if not user_id.isdigit():
        raise ValueError(f'cannot resolve the bot user of the GitHub App {app_slug}')
    return f'{app_slug}[bot]', f'{user_id}+{app_slug}[bot]@users.noreply.github.com'


def describe(version: str, tag: str) -> tuple[str, str]:
    # The tap keys automation on this exact title (for example, to skip review bots); keep it `openpath X.Y.Z`.
    title = f'openpath {version}'
    body = (f'openpath {tag} の Release に添付された `{CASK_ASSET}` を、そのまま `{CASK_PATH}` に反映します。\n\n'
            f'- Release: https://github.com/{SOURCE_REPO}/releases/tag/{tag}\n')
    run = [os.environ.get(name) for name in ('GITHUB_SERVER_URL', 'GITHUB_REPOSITORY', 'GITHUB_RUN_ID')]
    if all(run):
        body += f'- 作成した workflow run: {run[0]}/{run[1]}/actions/runs/{run[2]}\n'
    return title, body


def commit_and_push(work: pathlib.Path, base: str, branch: str, app_slug: str, message: tuple[str, str]) -> None:
    if git(work, 'status', '--porcelain').stdout.strip():
        name, email = bot_identity(app_slug)
        git(work, 'add', CASK_PATH)
        git(work, '-c', 'user.name=' + name, '-c', 'user.email=' + email,
            'commit', '--quiet', '-m', message[0], '-m', message[1])
        committed = True
    else:
        print(f'{branch} already has the version, sha256, and url of the release; no new commit.')
        committed = False
    changed = git(work, 'diff', '--name-only', f'origin/{base}...HEAD').stdout.split()
    if changed != [CASK_PATH]:
        raise ValueError(f'{branch} must change only {CASK_PATH}, but it changes {changed}')
    if committed:
        git(work, 'push', '--quiet', 'origin', f'HEAD:refs/heads/{branch}')
        print(f'Pushed {branch}.')


def open_pull_request(tap_repo: str, base: str, branch: str, message: tuple[str, str]) -> str:
    pulls = json.loads(gh('pr', 'list', '--repo', tap_repo, '--head', branch, '--base', base,
                          '--state', 'open', '--json', 'number,url,isCrossRepository'))
    own = [pull for pull in pulls if not pull['isCrossRepository']]
    if own:
        print(f'Reusing the open pull request {own[0]["url"]}.')
        return own[0]['url']
    url = gh('pr', 'create', '--repo', tap_repo, '--base', base, '--head', branch,
             '--title', message[0], '--body', message[1]).strip()
    print(f'Opened {url}.')
    return url


def request_auto_merge(url: str) -> None:
    """Leave the pull request open with a warning when the tap does not allow auto-merge."""
    try:
        gh('pr', 'merge', url, '--auto', '--squash')
    except subprocess.CalledProcessError:
        print(f'::warning::Auto-merge could not be requested for {url}. The pull request stays open; '
              'allow auto-merge in the tap or merge it after the required checks pass.')
        return
    print('Requested auto-merge (squash).')


def show_difference(current: str, cask: str) -> None:
    sys.stdout.writelines(difflib.unified_diff(current.splitlines(True), cask.splitlines(True),
                                               'a/' + CASK_PATH, 'b/' + CASK_PATH))


def compare_with_default_branch(current: str, cask: str, version: str, tag: str, tap_repo: str) -> str | None:
    """Return UNCHANGED or NEWER when the tap needs no pull request, or None when it is behind."""
    if current == cask:
        print(f'{CASK_PATH} already matches {tag}; nothing to do.')
        return UNCHANGED
    installed = cask_field(current, 'version')
    if is_newer(installed, version):
        print(f'::warning::{tap_repo} already has openpath {installed}, newer than {tag}; the tap is left as is.')
        return NEWER
    if installed != version:
        return None
    if release_fields(current) != release_fields(cask):
        raise ValueError(f'{tap_repo} has openpath {version} with a sha256 or url that differs from {tag}; '
                         'fix the tap by hand')
    print(f'{CASK_PATH} already has the version, sha256, and url of {tag}; '
          'the other lines were edited in the tap and are left as is:')
    show_difference(current, cask)
    return UNCHANGED


def update_tap(tag: str, directory: pathlib.Path, app_slug: str, dry_run: bool = False,
               tap_repo: str = TAP_REPO, tap_url: str | None = None) -> str:
    """Bring the tap to the verified cask of `tag` through a pull request; return the outcome."""
    version = verify_assets(directory, tag)
    if not APP_SLUG.match(app_slug):
        raise ValueError(f'invalid GitHub App slug {app_slug!r}')
    cask = (directory / CASK_ASSET).read_text()
    branch = f'openpath-v{version}'
    with tempfile.TemporaryDirectory(prefix='openpath-tap-') as temp:
        work = pathlib.Path(temp) / 'tap'
        git(pathlib.Path(temp), 'clone', '--quiet', tap_url or f'https://github.com/{tap_repo}.git', str(work))
        base = git(work, 'rev-parse', '--abbrev-ref', 'HEAD').stdout.strip()
        target = work / CASK_PATH
        current = target.read_text() if target.is_file() else ''
        print(f'Cloned {tap_repo} ({base}).')
        outcome = compare_with_default_branch(current, cask, version, tag, tap_repo)
        if outcome is not None:
            return outcome
        print(f'{CASK_PATH} differs from {tag}:')
        show_difference(current, cask)
        if dry_run:
            print('Dry run: no branch is pushed and no pull request is opened.')
            return DRY_RUN
        message = describe(version, tag)
        check_out_branch(work, branch)
        on_branch = target.read_text() if target.is_file() else ''
        if release_fields(on_branch) != release_fields(cask):
            target.parent.mkdir(exist_ok=True)
            target.write_text(cask)
        commit_and_push(work, base, branch, app_slug, message)
        request_auto_merge(open_pull_request(tap_repo, base, branch, message))
    return UPDATED


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    verify = commands.add_parser('verify', help='download and verify the assets of a published Stable release')
    verify.add_argument('--repo', default=SOURCE_REPO)
    update = commands.add_parser('update', help='open or update the pull request in the tap')
    update.add_argument('--app-slug', required=True)
    update.add_argument('--tap', default=TAP_REPO)
    update.add_argument('--dry-run', action='store_true')
    for command in (verify, update):
        command.add_argument('--tag', required=True)
        command.add_argument('--directory', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            version = fetch_release(args.repo, args.tag, args.directory)
            print(f'Verified the assets of {args.tag} (openpath {version}).')
        else:
            update_tap(args.tag, args.directory, args.app_slug, dry_run=args.dry_run, tap_repo=args.tap)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'error: Homebrew tap update failed: {error}\n')


if __name__ == '__main__':
    main()
