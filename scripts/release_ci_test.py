#!/usr/bin/env python3
"""Release gates run against isolated Git fixtures and a mocked GitHub CLI.

The Homebrew tap update runs against a tap in an isolated bare Git repository, with `gh` replaced by a recording fake.
It also checks the arguments scripts/test.sh passes to `swift test`, because the release workflow runs that script.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
import zipfile
from unittest.mock import patch

SCRIPTS = pathlib.Path(__file__).resolve().parent
WORKFLOWS = SCRIPTS.parent / '.github/workflows'
TAP_CASK_URL = 'https://github.com/TamaT-LLC/openpath/releases/download/v#{version}/openpath-#{version}.zip'
TAP_BRANCH = 'openpath-v1.2.3'
TAP_BOT = 'openpath-tap'
TAP_BOT_AUTHOR = 'openpath-tap[bot] <41898282+openpath-tap[bot]@users.noreply.github.com>'
TAP_PR_URL = 'https://github.com/TamaT-LLC/homebrew-tap/pull/7'


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {name} from {SCRIPTS}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        (self.root / 'Resources').mkdir()
        (self.root / 'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.3'}))
        (self.root / 'Sources/OpenPathCore').mkdir(parents=True)
        (self.root / 'Sources/OpenPathCore/AppInfo.swift').write_text('public static let version = "1.2.3"\n')
        self.git('add', '.')
        self.git('commit', '-m', 'initial')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL).decode().strip()

    def metadata(self, *args):
        result = subprocess.run(['python3', str(SCRIPTS / 'release_metadata.py'), *args], cwd=self.root, capture_output=True, text=True)
        return result, dict(line.split('=', 1) for line in result.stdout.splitlines())

    def test_smoke_does_not_require_tag(self):
        result, data = self.metadata('--smoke')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(data['channel'], 'smoke')
        self.assertEqual(data['asset_name'], 'openpath-1.2.3-smoke.zip')

    def test_stable_and_preview(self):
        for tag, channel, asset in [('v1.2.3', 'stable', 'openpath-1.2.3.zip'), ('preview-v1.2.3-2', 'preview', 'openpath-1.2.3-preview.2.zip')]:
            with self.subTest(tag=tag):
                self.git('tag', '-a', tag, '-m', tag)
                result, data = self.metadata('--tag', tag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(data['channel'], channel)
                self.assertEqual(data['asset_name'], asset)
                self.assertEqual(data['commit'], self.git('rev-parse', 'HEAD'))

    def test_rejects_invalid_tags(self):
        for tag in ['v01.2.3', 'v1.2.4', 'preview-v1.2.3-0', 'preview-v1.2.3-01', 'v1.2.3-rc.1']:
            with self.subTest(tag=tag):
                self.git('tag', '-a', tag, '-m', tag)
                self.assertNotEqual(self.metadata('--tag', tag)[0].returncode, 0)

    def test_rejects_lightweight_tag(self):
        self.git('tag', 'v1.2.3')
        self.assertNotEqual(self.metadata('--tag', 'v1.2.3')[0].returncode, 0)

    def test_rejects_commit_outside_main(self):
        (self.root / 'feature').touch()
        self.git('add', '.')
        self.git('commit', '-m', 'feature')
        self.git('tag', '-a', 'v1.2.3', '-m', 'stable')
        self.assertNotEqual(self.metadata('--tag', 'v1.2.3')[0].returncode, 0)

    def test_rejects_checkout_different_from_tag(self):
        self.git('tag', '-a', 'v1.2.3', '-m', 'stable')
        self.git('commit', '--allow-empty', '-m', 'next')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.assertNotEqual(self.metadata('--tag', 'v1.2.3')[0].returncode, 0)

    def test_rejects_app_version_mismatch(self):
        (self.root / 'Sources/OpenPathCore/AppInfo.swift').write_text('public static let version = "1.2.4"\n')
        self.git('add', '.')
        self.git('commit', '-m', 'mismatch')
        self.assertNotEqual(self.metadata('--smoke')[0].returncode, 0)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.module = load('publish_release')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)

    def fixture(self, stable=True):
        name = 'openpath-1.2.3.zip' if stable else 'openpath-1.2.3-preview.2.zip'
        (self.root / name).write_bytes(b'fixture archive')
        names = [name]
        if stable:
            (self.root / 'openpath.rb').write_text('fixture cask')
            names.append('openpath.rb')
        (self.root / 'SHA256SUMS').write_text(''.join(hashlib.sha256((self.root / n).read_bytes()).hexdigest() + '  ' + n + '\n' for n in names))
        return sorted(names + ['SHA256SUMS'])

    def test_stable_and_preview_publication_flags(self):
        for stable in [True, False]:
            with self.subTest(stable=stable):
                for item in self.root.iterdir():
                    item.unlink()
                names = self.fixture(stable)
                tag = 'v1.2.3' if stable else 'preview-v1.2.3-2'
                draft = json.dumps({'isDraft': True, 'assets': [{'name': n} for n in names]})
                published = json.dumps({'isDraft': False, 'isPrerelease': not stable, 'assets': [{'name': n} for n in names]})
                with patch.object(self.module, 'gh', side_effect=['', '', draft, '', published]) as gh:
                    self.module.publish('TamaT-LLC/openpath', tag, self.root)
                    calls = [c.args for c in gh.call_args_list]
                    self.assertIn('--draft', calls[1])
                    self.assertIn('--latest=true' if stable else '--latest=false', calls[3])
                    self.assertIn('--prerelease=false' if stable else '--prerelease=true', calls[3])

    def test_existing_release_is_not_overwritten(self):
        self.fixture()
        with patch.object(self.module, 'gh', return_value='v1.2.3\n') as gh:
            with self.assertRaises(ValueError):
                self.module.publish('TamaT-LLC/openpath', 'v1.2.3', self.root)
            self.assertEqual(gh.call_count, 1)

    def test_missing_modified_or_unexpected_assets_fail_before_network(self):
        for change in ['missing', 'modified', 'extra']:
            with self.subTest(change=change):
                for item in self.root.iterdir():
                    item.unlink()
                self.fixture()
                if change == 'missing':
                    (self.root / 'openpath.rb').unlink()
                elif change == 'modified':
                    (self.root / 'openpath-1.2.3.zip').write_bytes(b'tampered')
                else:
                    (self.root / 'secret.p8').touch()
                with patch.object(self.module, 'gh') as gh:
                    with self.assertRaises(ValueError):
                        self.module.publish('TamaT-LLC/openpath', 'v1.2.3', self.root)
                    gh.assert_not_called()

    def test_github_api_failure_does_not_create_release(self):
        self.fixture()
        with patch.object(self.module, 'gh', side_effect=subprocess.CalledProcessError(1, 'gh')) as gh:
            with self.assertRaises(subprocess.CalledProcessError):
                self.module.publish('TamaT-LLC/openpath', 'v1.2.3', self.root)
            self.assertEqual(gh.call_count, 1)

    def test_smoke_cannot_be_published(self):
        with patch.object(self.module, 'gh') as gh:
            with self.assertRaises(ValueError):
                self.module.publish('TamaT-LLC/openpath', 'smoke', self.root)
            gh.assert_not_called()

    def test_incomplete_upload_stays_draft(self):
        self.fixture()
        with patch.object(self.module, 'gh', side_effect=['', '', json.dumps({'isDraft': True, 'assets': []})]) as gh:
            with self.assertRaises(ValueError):
                self.module.publish('TamaT-LLC/openpath', 'v1.2.3', self.root)
            self.assertEqual(gh.call_count, 3)


class CleanupTests(unittest.TestCase):
    def test_all_cleanup_operations_are_attempted_even_after_failure(self):
        workflow = (SCRIPTS.parent / '.github/workflows/release.yml').read_text()
        section = workflow.split('      - name: Remove signing credentials\n', 1)[1]
        body = section.split('        run: |\n', 1)[1].split('\n  publish:', 1)[0]
        script = textwrap.dedent(body)
        for failures in ['', 'python3', 'security', 'rm', 'python3 security rm']:
            with self.subTest(failures=failures), tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp)
                credentials = root / 'openpath-signing'
                credentials.mkdir()
                for name in ['original-keychains.txt', 'signing.keychain-db', 'AuthKey.p8']:
                    (credentials / name).write_text('fixture')
                commands = root / 'bin'
                commands.mkdir()
                log = root / 'calls'
                for name in ['python3', 'security', 'rm']:
                    stub = commands / name
                    stub.write_text('#!/bin/bash\n'
                                    + f'echo {name} >> "$CALL_LOG"\n'
                                    + f'case " $FAIL_COMMANDS " in *" {name} "*) exit 7;; esac\n'
                                    + ('exec /bin/rm "$@"\n' if name == 'rm' else 'exit 0\n'))
                    stub.chmod(0o755)
                env = dict(os.environ, RUNNER_TEMP=temp, CALL_LOG=str(log), FAIL_COMMANDS=failures,
                           PATH=str(commands) + ':' + os.environ['PATH'])
                result = subprocess.run(['/bin/bash', '-e', '-o', 'pipefail', '-c', script], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(log.read_text().splitlines(), ['python3', 'security', 'rm'])
                self.assertEqual(result.returncode, 1 if failures else 0, result.stderr)
                if 'rm' not in failures:
                    self.assertFalse(credentials.exists())


def tap_cask(version, sha256, url=TAP_CASK_URL):
    """A cask in the shape scripts/cask.sh writes."""
    return (f'cask "openpath" do\n  version "{version}"\n  sha256 "{sha256}"\n\n  url "{url}"\n'
            '  name "openpath"\n\n  livecheck do\n    url :url\n    strategy :github_latest\n  end\n\n'
            '  app "openpath.app"\nend\n')


def tap_side_fix(cask):
    """The cask after a tap-side edit outside version, sha256, and url, which the tap's release check allows."""
    return cask.replace('  app "openpath.app"\n', '  depends_on macos: :sonoma\n\n  app "openpath.app"\n')


@unittest.skipUnless(shutil.which('plutil'), 'scripts/cask.sh reads Info.plist with the macOS plutil')
class CaskScriptTests(unittest.TestCase):
    def test_generated_cask_requires_sonoma_or_later_and_matches_its_zip(self):
        with tempfile.TemporaryDirectory() as temp:
            assets = pathlib.Path(temp)
            archive = assets / 'openpath-1.2.3.zip'
            info = {'CFBundleShortVersionString': '1.2.3', 'CFBundleIdentifier': 'jp.tamat.openpath',
                    'LSMinimumSystemVersion': '14.0'}
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('openpath.app/Contents/Info.plist', plistlib.dumps(info))
            result = subprocess.run([str(SCRIPTS / 'cask.sh'), '--version', '1.2.3', '--zip', str(archive),
                                     '--output', str(assets / 'openpath.rb')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = (assets / 'openpath.rb').read_text()
            # Homebrew 6.0 deprecates `">= :sonoma"`; a bare symbol now means "Sonoma or later".
            self.assertIn('\n  depends_on macos: :sonoma\n', text)
            self.assertNotIn('>=', text)
            (assets / 'SHA256SUMS').write_text(''.join(
                hashlib.sha256((assets / name).read_bytes()).hexdigest() + '  ' + name + '\n'
                for name in ['openpath-1.2.3.zip', 'openpath.rb']))
            self.assertEqual(load('update_homebrew_tap').verify_assets(assets, 'v1.2.3'), '1.2.3')


class HomebrewTapFixture(unittest.TestCase):
    """Release assets in a directory and the tap in an isolated bare repository; `gh` is a recording fake."""

    def setUp(self):
        self.module = load('update_homebrew_tap')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        config = self.root / 'gitconfig'
        config.write_text('[user]\n\tname = Tap Test\n\temail = tap-test@example.invalid\n')
        environment = patch.dict(os.environ, {'GIT_CONFIG_GLOBAL': str(config), 'GIT_CONFIG_NOSYSTEM': '1'})
        environment.start()
        self.addCleanup(environment.stop)
        self.assets = self.root / 'release'
        self.bare = self.root / 'tap.git'
        self.calls = []

    def git(self, cwd, *args):
        return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout

    def write_release(self, cask_version='1.2.3', cask_sha=None, url=TAP_CASK_URL):
        """Write the assets of v1.2.3 with a consistent SHA256SUMS and return the cask text."""
        self.assets.mkdir(exist_ok=True)
        for item in self.assets.iterdir():
            item.unlink()
        archive = self.assets / 'openpath-1.2.3.zip'
        archive.write_bytes(b'fixture archive')
        text = tap_cask(cask_version, cask_sha or hashlib.sha256(b'fixture archive').hexdigest(), url)
        (self.assets / 'openpath.rb').write_text(text)
        (self.assets / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.assets / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in ['openpath-1.2.3.zip', 'openpath.rb']))
        return text

    def write_tap(self, cask, branch_files=None):
        """Create the tap with `cask` on main and, optionally, an existing openpath-v1.2.3 branch."""
        seed = self.root / 'seed'
        self.git(self.root, 'init', '--quiet', '-b', 'main', str(seed))
        (seed / 'README.md').write_text('tap\n')
        (seed / 'Casks').mkdir()
        (seed / 'Casks/openpath.rb').write_text(cask)
        self.git(seed, 'add', '.')
        self.git(seed, 'commit', '--quiet', '-m', 'initial')
        self.git(self.root, 'init', '--quiet', '--bare', '-b', 'main', str(self.bare))
        self.git(seed, 'push', '--quiet', str(self.bare), 'main')
        if branch_files:
            self.git(seed, 'switch', '--quiet', '-c', TAP_BRANCH)
            for name, text in branch_files.items():
                (seed / name).write_text(text)
            self.git(seed, 'commit', '--quiet', '-am', 'existing branch')
            self.git(seed, 'push', '--quiet', str(self.bare), TAP_BRANCH)

    def tap_git(self, *args):
        return self.git(self.root, '--git-dir', str(self.bare), *args)

    def rev(self, ref):
        return self.tap_git('rev-parse', ref).strip()

    def branches(self):
        return self.tap_git('for-each-ref', '--format=%(refname:short)', 'refs/heads').split()

    def fake_gh(self, pulls=(), merge_error=False):
        def gh(*args):
            self.calls.append(args)
            if args == ('api', f'users/{TAP_BOT}[bot]', '--jq', '.id'):
                return '41898282\n'
            if args[:2] == ('pr', 'list'):
                return json.dumps(list(pulls))
            if args[:2] == ('pr', 'create'):
                return TAP_PR_URL + '\n'
            if args[:2] == ('pr', 'merge'):
                if merge_error:
                    raise subprocess.CalledProcessError(1, ['gh', *args])
                return ''
            raise AssertionError(f'unexpected gh call: {args}')
        return patch.object(self.module, 'gh', side_effect=gh)

    def update(self, dry_run=False, slug=TAP_BOT, **gh_options):
        output = io.StringIO()
        with self.fake_gh(**gh_options), contextlib.redirect_stdout(output):
            status = self.module.update_tap('v1.2.3', self.assets, slug, dry_run=dry_run, tap_url=str(self.bare))
        return status, output.getvalue()

    def commands(self):
        return [call[:2] for call in self.calls]


class HomebrewTapVerificationTests(HomebrewTapFixture):
    def release_view(self, **overrides):
        release = {'tagName': 'v1.2.3', 'isDraft': False, 'isPrerelease': False,
                   'assets': [{'name': n} for n in ['SHA256SUMS', 'openpath-1.2.3.zip', 'openpath.rb']]}
        release.update(overrides)
        return json.dumps(release)

    def test_consistent_assets_return_the_version(self):
        self.write_release()
        self.assertEqual(self.module.verify_assets(self.assets, 'v1.2.3'), '1.2.3')

    def test_any_mismatch_between_tag_checksums_zip_and_cask_fails(self):
        def tamper(name):
            return lambda: (self.assets / name).write_bytes(b'tampered')
        cases = [
            ('ZIP differs from SHA256SUMS', 'SHA256SUMS', tamper('openpath-1.2.3.zip')),
            ('cask differs from SHA256SUMS', 'SHA256SUMS', tamper('openpath.rb')),
            ('cask version differs from the tag', 'cask version', lambda: self.write_release(cask_version='1.2.4')),
            ('cask sha256 differs from the ZIP', 'cask sha256', lambda: self.write_release(cask_sha='0' * 64)),
            ('cask url points elsewhere', 'cask url',
             lambda: self.write_release(url='https://example.com/openpath-#{version}.zip')),
            ('extra asset', 'missing or unexpected', lambda: (self.assets / 'secret.p8').write_text('key')),
            ('missing cask', 'missing or unexpected', lambda: (self.assets / 'openpath.rb').unlink()),
        ]
        for name, message, arrange in cases:
            with self.subTest(name):
                self.write_release()
                arrange()
                with self.assertRaisesRegex(ValueError, message):
                    self.module.verify_assets(self.assets, 'v1.2.3')

    def test_preview_and_malformed_tags_are_rejected_before_any_network_access(self):
        self.write_release()
        for tag in ['preview-v1.2.3-2', 'v1.2', 'v01.2.3', 'smoke']:
            with self.subTest(tag=tag), patch.object(self.module, 'gh') as gh:
                with self.assertRaises(ValueError):
                    self.module.fetch_release('TamaT-LLC/openpath', tag, self.root / 'download')
                with self.assertRaises(ValueError):
                    self.module.update_tap(tag, self.assets, TAP_BOT, tap_url=str(self.root / 'missing.git'))
                gh.assert_not_called()

    def test_only_a_published_stable_release_with_the_expected_assets_is_downloaded(self):
        expected = [{'name': n} for n in ['SHA256SUMS', 'openpath-1.2.3.zip', 'openpath.rb']]
        for name, overrides in [('prerelease', {'isPrerelease': True}), ('draft', {'isDraft': True}),
                                ('other tag', {'tagName': 'v1.2.4'}), ('missing cask', {'assets': expected[:2]}),
                                ('extra asset', {'assets': expected + [{'name': 'secret.p8'}]})]:
            with self.subTest(name), patch.object(self.module, 'gh', return_value=self.release_view(**overrides)) as gh:
                with self.assertRaises(ValueError):
                    self.module.fetch_release('TamaT-LLC/openpath', 'v1.2.3', self.root / 'download')
                self.assertEqual(gh.call_count, 1)

    def test_downloaded_assets_are_verified(self):
        self.write_release()
        for tampered in [False, True]:
            download = self.root / f'download-{tampered}'

            def gh(*args):
                if args[:2] != ('release', 'download'):
                    return self.release_view()
                for item in self.assets.iterdir():
                    shutil.copy(item, download / item.name)
                if tampered:
                    (download / 'openpath-1.2.3.zip').write_bytes(b'tampered')
                return ''
            with self.subTest(tampered=tampered), patch.object(self.module, 'gh', side_effect=gh) as mock:
                if tampered:
                    with self.assertRaisesRegex(ValueError, 'SHA256SUMS'):
                        self.module.fetch_release('TamaT-LLC/openpath', 'v1.2.3', download)
                else:
                    self.assertEqual(self.module.fetch_release('TamaT-LLC/openpath', 'v1.2.3', download), '1.2.3')
                args = mock.call_args_list[1].args
                self.assertEqual(args[:6], ('release', 'download', 'v1.2.3', '--repo', 'TamaT-LLC/openpath', '--dir'))
                patterns = sorted(args[i + 1] for i, arg in enumerate(args) if arg == '--pattern')
                self.assertEqual(patterns, ['SHA256SUMS', 'openpath-1.2.3.zip', 'openpath.rb'])


class HomebrewTapUpdateTests(HomebrewTapFixture):
    def test_identical_cask_leaves_the_tap_untouched(self):
        self.write_tap(self.write_release())
        main = self.rev('main')
        for dry_run in [False, True]:
            with self.subTest(dry_run=dry_run):
                status, _ = self.update(dry_run=dry_run)
                self.assertEqual(status, 'unchanged')
                self.assertEqual(self.calls, [])
                self.assertEqual(self.branches(), ['main'])
                self.assertEqual(self.rev('main'), main)

    def test_same_version_with_tap_side_edits_is_left_as_is(self):
        self.write_tap(tap_side_fix(self.write_release()))
        main = self.rev('main')
        for dry_run in [False, True]:
            with self.subTest(dry_run=dry_run):
                status, output = self.update(dry_run=dry_run)
                self.assertEqual(status, 'unchanged')
                self.assertIn('depends_on macos: :sonoma', output)
                self.assertEqual(self.calls, [])
                self.assertEqual(self.branches(), ['main'])
                self.assertEqual(self.rev('main'), main)

    def test_same_version_with_another_sha256_or_url_fails(self):
        self.write_release()
        self.write_tap(tap_cask('1.2.3', '9' * 64))
        with self.assertRaisesRegex(ValueError, 'sha256 or url'):
            self.update()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.branches(), ['main'])

    def test_newer_cask_in_the_tap_is_not_downgraded(self):
        self.write_release()
        self.write_tap(tap_cask('1.2.10', '1' * 64))
        status, output = self.update()
        self.assertEqual(status, 'newer')
        self.assertIn('::warning::', output)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.branches(), ['main'])

    def test_dry_run_reports_the_difference_without_pushing(self):
        self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64))
        status, output = self.update(dry_run=True)
        self.assertEqual(status, 'dry-run')
        self.assertIn('-  version "1.2.2"', output)
        self.assertIn('+  version "1.2.3"', output)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.branches(), ['main'])

    def test_new_branch_and_pull_request_request_auto_merge(self):
        release = self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64))
        fork = {'number': 3, 'url': 'https://github.com/someone/homebrew-tap/pull/3', 'isCrossRepository': True}
        status, output = self.update(pulls=[fork])
        self.assertEqual(status, 'updated')
        self.assertEqual(self.branches(), ['main', TAP_BRANCH])
        self.assertEqual(self.tap_git('show', f'{TAP_BRANCH}:Casks/openpath.rb'), release)
        self.assertEqual(self.tap_git('diff', '--name-only', f'main...{TAP_BRANCH}').split(), ['Casks/openpath.rb'])
        self.assertEqual(self.rev(f'{TAP_BRANCH}^'), self.rev('main'))
        identities = self.tap_git('log', '-1', '--format=%an <%ae>%n%cn <%ce>', TAP_BRANCH).splitlines()
        self.assertEqual(identities, [TAP_BOT_AUTHOR, TAP_BOT_AUTHOR])
        self.assertEqual(self.tap_git('log', '-1', '--format=%s', TAP_BRANCH).strip(), 'openpath 1.2.3')
        create = next(call for call in self.calls if call[:2] == ('pr', 'create'))
        options = dict(zip(create[2::2], create[3::2]))
        self.assertEqual((options['--repo'], options['--base'], options['--head'], options['--title']),
                         ('TamaT-LLC/homebrew-tap', 'main', TAP_BRANCH, 'openpath 1.2.3'))
        self.assertIn(('pr', 'merge', TAP_PR_URL, '--auto', '--squash'), self.calls)
        self.assertNotIn('::warning::', output)

    def test_existing_branch_and_pull_request_are_updated_in_place(self):
        release = self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64), {'Casks/openpath.rb': tap_cask('1.2.3', '3' * 64)})
        previous = self.rev(TAP_BRANCH)
        existing = 'https://github.com/TamaT-LLC/homebrew-tap/pull/5'
        status, _ = self.update(pulls=[{'number': 5, 'url': existing, 'isCrossRepository': False}])
        self.assertEqual(status, 'updated')
        self.assertEqual(self.rev(f'{TAP_BRANCH}^'), previous)
        self.assertEqual(self.tap_git('show', f'{TAP_BRANCH}:Casks/openpath.rb'), release)
        self.assertNotIn(('pr', 'create'), self.commands())
        self.assertIn(('pr', 'merge', existing, '--auto', '--squash'), self.calls)

    def test_existing_branch_with_the_cask_gets_a_pull_request_without_a_new_commit(self):
        release = self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64), {'Casks/openpath.rb': release})
        previous = self.rev(TAP_BRANCH)
        status, _ = self.update()
        self.assertEqual(status, 'updated')
        self.assertEqual(self.rev(TAP_BRANCH), previous)
        self.assertEqual(self.commands(), [('pr', 'list'), ('pr', 'create'), ('pr', 'merge')])

    def test_tap_side_fix_on_the_existing_branch_is_kept(self):
        release = self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64), {'Casks/openpath.rb': tap_side_fix(release)})
        previous = self.rev(TAP_BRANCH)
        status, _ = self.update()
        self.assertEqual(status, 'updated')
        self.assertEqual(self.rev(TAP_BRANCH), previous)
        self.assertEqual(self.tap_git('show', f'{TAP_BRANCH}:Casks/openpath.rb'), tap_side_fix(release))
        self.assertEqual(self.commands(), [('pr', 'list'), ('pr', 'create'), ('pr', 'merge')])

    def test_branch_changing_other_files_is_rejected_before_push(self):
        self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64), {'README.md': 'changed\n'})
        previous = self.rev(TAP_BRANCH)
        with self.assertRaisesRegex(ValueError, 'only Casks/openpath.rb'):
            self.update()
        self.assertEqual(self.rev(TAP_BRANCH), previous)
        self.assertNotIn(('pr', 'create'), self.commands())

    def test_rejected_auto_merge_leaves_the_pull_request_with_a_warning(self):
        self.write_release()
        self.write_tap(tap_cask('1.2.2', '2' * 64))
        status, output = self.update(merge_error=True)
        self.assertEqual(status, 'updated')
        self.assertIn('::warning::', output)
        self.assertIn(TAP_PR_URL, output)
        self.assertEqual(self.branches(), ['main', TAP_BRANCH])

    def test_invalid_app_slug_is_rejected_before_cloning(self):
        self.write_release()
        with self.assertRaisesRegex(ValueError, 'slug'):
            self.update(slug='bad slug')
        self.assertEqual(self.calls, [])


class HomebrewTapWorkflowTests(unittest.TestCase):
    def release_job(self, name):
        text = (WORKFLOWS / 'release.yml').read_text()
        return re.split(r'\n  [^ \n][^\n]*:\n', text.split(f'\n  {name}:\n', 1)[1], maxsplit=1)[0]

    def test_release_calls_the_tap_workflow_only_after_a_stable_publish(self):
        job = self.release_job('homebrew-tap')
        lines = [line.strip() for line in job.splitlines()]
        self.assertIn('needs: [prepare, publish]', lines)
        condition = next(line for line in lines if line.startswith('if:'))
        self.assertIn("needs.prepare.outputs.channel == 'stable'", condition)
        self.assertIn("needs.publish.result == 'success'", condition)
        self.assertIn('uses: ./.github/workflows/homebrew-tap.yml', lines)
        self.assertIn('tag: ${{ github.ref_name }}', lines)
        self.assertEqual([line.strip() for line in job.split('\n    secrets:\n', 1)[1].splitlines() if line.strip()],
                         ['HOMEBREW_TAP_APP_PRIVATE_KEY: ${{ secrets.HOMEBREW_TAP_APP_PRIVATE_KEY }}'])

    def test_the_app_private_key_is_passed_explicitly_and_only_to_the_tap_job(self):
        release = (WORKFLOWS / 'release.yml').read_text()
        self.assertEqual(release.count('HOMEBREW_TAP_APP_PRIVATE_KEY'), 2)
        self.assertEqual(self.release_job('homebrew-tap').count('HOMEBREW_TAP_APP_PRIVATE_KEY'), 2)
        for workflow in WORKFLOWS.glob('*.yml'):
            self.assertNotRegex(workflow.read_text(), r'secrets: *inherit', workflow.name)

    def test_tap_token_is_scoped_to_the_tap_and_the_key_stays_out_of_run_steps(self):
        text = (WORKFLOWS / 'homebrew-tap.yml').read_text()
        step = text.split('uses: actions/create-github-app-token@', 1)[1].split('\n      - ', 1)[0]
        settings = dict(line.strip().split(': ', 1) for line in step.splitlines()[1:] if ': ' in line)
        self.assertEqual(settings['client-id'], '${{ vars.HOMEBREW_TAP_APP_CLIENT_ID }}')
        self.assertEqual(settings['owner'], 'TamaT-LLC')
        self.assertEqual(settings['repositories'], 'homebrew-tap')
        self.assertEqual(settings['permission-contents'], 'write')
        self.assertEqual(settings['permission-pull-requests'], 'write')
        references = [line.strip() for line in text.splitlines() if 'secrets.HOMEBREW_TAP_APP_PRIVATE_KEY' in line]
        self.assertEqual(references, ["HAS_PRIVATE_KEY: ${{ secrets.HOMEBREW_TAP_APP_PRIVATE_KEY != '' }}",
                                      'private-key: ${{ secrets.HOMEBREW_TAP_APP_PRIVATE_KEY }}'])


class TestScriptTests(unittest.TestCase):
    """scripts/test.sh が CLT の構成ごとに `swift test` へ渡す引数を、swift をスタブに差し替えて確かめる。

    CLT のパスは OPENPATH_TEST_CLT_DIR で一時ディレクトリに差し替えるため、開発機の CLT には触れない。
    macOS 標準の bash 3.2 でも set -u の下で動くことを確かめるため、/bin/bash で実行する。
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.clt = self.root / 'CommandLineTools'
        self.frameworks = self.clt / 'Library/Developer/Frameworks'
        self.usr_lib = self.clt / 'Library/Developer/usr/lib'
        self.log = self.root / 'swift-args'
        commands = self.root / 'bin'
        commands.mkdir()
        stub = commands / 'swift'
        stub.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$ARGS_LOG"\n')
        stub.chmod(0o755)
        self.commands = commands

    def install_testing_framework(self):
        (self.frameworks / 'Testing.framework').mkdir(parents=True)

    def install_testing_interop(self):
        self.usr_lib.mkdir(parents=True)
        (self.usr_lib / 'lib_TestingInterop.dylib').touch()

    def swift_args(self, *args, developer_dir=None):
        env = dict(os.environ, OPENPATH_TEST_CLT_DIR=str(self.clt), ARGS_LOG=str(self.log),
                   DEVELOPER_DIR=str(self.clt) if developer_dir is None else developer_dir,
                   PATH=str(self.commands) + ':' + os.environ['PATH'])
        result = subprocess.run(['/bin/bash', str(SCRIPTS / 'test.sh'), *args], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.log.read_text().splitlines()

    def clt_args(self):
        return ['test',
                '-Xswiftc', '-F', '-Xswiftc', str(self.frameworks),
                '-Xlinker', '-rpath', '-Xlinker', str(self.frameworks),
                '-Xswiftc', '-Xfrontend', '-Xswiftc', '-disable-cross-import-overlays']

    def test_clt_without_testing_interop_keeps_existing_arguments(self):
        self.install_testing_framework()
        self.assertEqual(self.swift_args(), self.clt_args())

    def test_clt_with_testing_interop_adds_its_directory_to_rpath(self):
        self.install_testing_framework()
        self.install_testing_interop()
        self.assertEqual(self.swift_args(), self.clt_args() + ['-Xlinker', '-rpath', '-Xlinker', str(self.usr_lib)])

    def test_user_arguments_follow_the_added_ones(self):
        self.install_testing_framework()
        self.install_testing_interop()
        args = self.swift_args('--filter', 'AppInfo')
        self.assertEqual(args[-2:], ['--filter', 'AppInfo'])
        self.assertIn(str(self.usr_lib), args)

    def test_interop_directory_is_ignored_without_testing_framework(self):
        self.install_testing_interop()
        self.assertEqual(self.swift_args('--filter', 'AppInfo'), ['test', '--filter', 'AppInfo'])

    def test_xcode_toolchain_passes_arguments_through_unchanged(self):
        self.install_testing_framework()
        self.install_testing_interop()
        xcode = '/Applications/Xcode.app/Contents/Developer'
        self.assertEqual(self.swift_args(developer_dir=xcode), ['test'])
        self.assertEqual(self.swift_args('--filter', 'AppInfo', developer_dir=xcode), ['test', '--filter', 'AppInfo'])


if __name__ == '__main__':
    unittest.main()
