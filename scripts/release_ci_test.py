#!/usr/bin/env python3
"""Release gates run against isolated Git fixtures and a mocked GitHub CLI."""
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch

SCRIPTS = pathlib.Path(__file__).resolve().parent


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


if __name__ == '__main__':
    unittest.main()
