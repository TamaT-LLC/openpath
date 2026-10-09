#!/usr/bin/env python3
"""Tests for the release notes list in the documentation index."""
import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {name} from {SCRIPTS}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


notes = load('release_notes_index')

BEGIN = '<!-- release-notes:begin -->'
END = '<!-- release-notes:end -->'

INDEX = f'''# ドキュメントインデックス

## リリースノート

{BEGIN}
- [古い一覧](../releases/v0.0.1.md)
{END}

## プロジェクトの運用
'''


class Repo:
    """A throwaway repository layout with docs/releases and docs/00_index."""

    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.releases = self.root / 'docs' / 'releases'
        self.releases.mkdir(parents=True)
        self.index = self.root / 'docs' / '00_index' / 'index.md'
        self.index.parent.mkdir(parents=True)
        self.index.write_text(INDEX)
        self.note('unreleased.md', '# 未リリースの変更\n')

    def note(self, name, text):
        (self.releases / name).write_text(text)

    def run(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = notes.main(list(args), root=self.root)
        return code, stdout.getvalue(), stderr.getvalue()


class ReleaseNotesIndexTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Repo(self.temp.name)

    def block_lines(self):
        text = self.repo.index.read_text()
        return text.split(BEGIN + '\n', 1)[1].split(END, 1)[0].splitlines()

    def test_versions_are_sorted_numerically_oldest_first(self):
        for version in ('0.1.10', '0.1.9', '0.2.0', '0.1.0'):
            self.repo.note(f'v{version}.md', f'# v{version}\n')

        entries = notes.collect(self.repo.releases)

        self.assertEqual([entry.version for entry in entries],
                         ['0.1.0', '0.1.9', '0.1.10', '0.2.0'])

    def test_non_version_files_are_ignored(self):
        self.repo.note('v0.1.0.md', '# v0.1.0\n')
        self.repo.note('v0.1.md', '# v0.1\n')
        self.repo.note('v01.1.0.md', '# v01.1.0\n')
        self.repo.note('notes.md', '# notes\n')

        entries = notes.collect(self.repo.releases)

        self.assertEqual([entry.version for entry in entries], ['0.1.0'])

    def test_summary_comes_from_the_parenthesis_in_the_heading(self):
        self.repo.note('v0.1.0.md', '# v0.1.0（最初の Stable）\n\n本文。\n')

        [entry] = notes.collect(self.repo.releases)

        self.assertEqual(entry.summary, '最初の Stable')
        self.assertEqual(notes.link(entry),
                         '- [v0.1.0 のリリースノート（最初の Stable）](../releases/v0.1.0.md)')

    def test_heading_without_parenthesis_has_no_summary(self):
        self.repo.note('v0.1.1.md', '# v0.1.1\n\n`v0.1.1` は、Stable である。\n')

        [entry] = notes.collect(self.repo.releases)

        self.assertEqual(entry.summary, '')
        self.assertEqual(notes.link(entry), '- [v0.1.1 のリリースノート](../releases/v0.1.1.md)')

    def test_heading_must_name_the_version_of_the_file(self):
        self.repo.note('v0.1.3.md', '# 未リリース（`v0.1.3` に向けた変更）\n')

        with self.assertRaisesRegex(notes.ReleaseNotesError, 'v0.1.3.md'):
            notes.collect(self.repo.releases)

    def test_heading_must_be_the_first_line(self):
        self.repo.note('v0.1.0.md', '本文。\n# v0.1.0\n')

        with self.assertRaisesRegex(notes.ReleaseNotesError, 'v0.1.0.md'):
            notes.collect(self.repo.releases)

    def test_write_replaces_only_the_marked_block_and_keeps_unreleased_last(self):
        self.repo.note('v0.1.10.md', '# v0.1.10\n')
        self.repo.note('v0.1.9.md', '# v0.1.9（修正）\n')

        code, _, stderr = self.repo.run()

        self.assertEqual(code, 0, stderr)
        self.assertEqual(self.block_lines(), [
            '- [v0.1.9 のリリースノート（修正）](../releases/v0.1.9.md)',
            '- [v0.1.10 のリリースノート](../releases/v0.1.10.md)',
            '- [未リリースの変更](../releases/unreleased.md)',
        ])
        text = self.repo.index.read_text()
        self.assertTrue(text.startswith('# ドキュメントインデックス\n\n## リリースノート\n\n' + BEGIN + '\n'))
        self.assertTrue(text.endswith(END + '\n\n## プロジェクトの運用\n'))

    def test_unreleased_is_listed_even_without_versioned_notes(self):
        code, _, stderr = self.repo.run()

        self.assertEqual(code, 0, stderr)
        self.assertEqual(self.block_lines(), ['- [未リリースの変更](../releases/unreleased.md)'])

    def test_missing_unreleased_note_is_an_error(self):
        (self.repo.releases / 'unreleased.md').unlink()

        code, _, stderr = self.repo.run()

        self.assertEqual(code, 1)
        self.assertIn('unreleased.md', stderr)

    def test_write_is_idempotent(self):
        self.repo.note('v0.1.0.md', '# v0.1.0（最初の Stable）\n')
        self.repo.run()
        first = self.repo.index.read_text()

        code, _, stderr = self.repo.run()

        self.assertEqual(code, 0, stderr)
        self.assertEqual(self.repo.index.read_text(), first)

    def test_missing_marker_is_an_error(self):
        for missing in (BEGIN, END):
            with self.subTest(missing=missing):
                self.repo.index.write_text(INDEX.replace(missing + '\n', ''))

                code, _, stderr = self.repo.run()

                self.assertEqual(code, 1)
                self.assertIn(missing, stderr)

    def test_duplicated_marker_is_an_error(self):
        for marker in (BEGIN, END):
            with self.subTest(marker=marker):
                self.repo.index.write_text(INDEX.replace(marker, marker + '\n' + marker))

                code, _, stderr = self.repo.run()

                self.assertEqual(code, 1)
                self.assertIn(marker, stderr)

    def test_markers_in_the_wrong_order_are_an_error(self):
        swapped = INDEX.replace(BEGIN, '@@').replace(END, BEGIN).replace('@@', END)
        self.repo.index.write_text(swapped)

        code, _, stderr = self.repo.run()

        self.assertEqual(code, 1)
        self.assertIn(BEGIN, stderr)

    def test_errors_leave_the_index_untouched(self):
        self.repo.note('v0.1.0.md', 'no heading\n')

        code, _, _ = self.repo.run()

        self.assertEqual(code, 1)
        self.assertEqual(self.repo.index.read_text(), INDEX)

    def test_check_reports_a_stale_index_without_writing(self):
        self.repo.note('v0.1.0.md', '# v0.1.0\n')

        code, _, stderr = self.repo.run('--check')

        self.assertEqual(code, 1)
        self.assertEqual(self.repo.index.read_text(), INDEX)
        self.assertIn('-- [古い一覧](../releases/v0.0.1.md)', stderr)
        self.assertIn('+- [v0.1.0 のリリースノート](../releases/v0.1.0.md)', stderr)
        self.assertIn('python3 scripts/release_notes_index.py', stderr)

    def test_check_passes_when_the_index_is_current(self):
        self.repo.note('v0.1.0.md', '# v0.1.0\n')
        self.repo.run()

        code, stdout, stderr = self.repo.run('--check')

        self.assertEqual(code, 0, stderr)
        self.assertEqual(stderr, '')
        self.assertIn('up to date', stdout)


if __name__ == '__main__':
    unittest.main()
