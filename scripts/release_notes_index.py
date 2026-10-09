#!/usr/bin/env python3
"""Generate the release notes list in docs/00_index/index.md.

The list sits between the `<!-- release-notes:begin -->` and
`<!-- release-notes:end -->` markers and is rebuilt from docs/releases:

- every `vX.Y.Z.md` (no leading zeroes), oldest first by numeric version;
- the link text is `vX.Y.Z のリリースノート`, followed by the parenthesis of
  the note's heading when it has one (`# v0.1.0（最初の Stable）`);
- `unreleased.md` always comes last, without a version name.

The first line of each `vX.Y.Z.md` must be `# vX.Y.Z` or `# vX.Y.Z（...）`, so
a renamed unreleased.md whose heading was not rewritten is rejected.

Without options the index is rewritten in place. With `--check` nothing is
written; a stale index prints a diff and exits 1 (CI runs this mode).
"""
from __future__ import annotations

import argparse
import difflib
import pathlib
import re
import sys
from typing import NamedTuple

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX_FILE = 'docs/00_index/index.md'
RELEASES_DIR = 'docs/releases'
UNRELEASED_FILE = 'unreleased.md'
# Links are written relative to INDEX_FILE.
RELEASES_LINK = '../releases/'
BEGIN_MARKER = '<!-- release-notes:begin -->'
END_MARKER = '<!-- release-notes:end -->'
REGENERATE_COMMAND = 'python3 scripts/release_notes_index.py'

VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
NOTE_NAME = re.compile(r'v(' + VERSION + r')\.md\Z')
HEADING = re.compile(r'# v(?P<version>' + VERSION + r')(?:（(?P<summary>[^（）]+)）)?\Z')


class ReleaseNotesError(Exception):
    """The release notes or the index cannot be turned into a list."""


class Entry(NamedTuple):
    version: str
    summary: str

    @property
    def key(self) -> tuple[int, ...]:
        return tuple(int(part) for part in self.version.split('.'))


def read_entry(path: pathlib.Path, version: str) -> Entry:
    first_line = path.read_text(encoding='utf-8').split('\n', 1)[0].rstrip()
    heading = HEADING.fullmatch(first_line)
    if not heading or heading['version'] != version:
        raise ReleaseNotesError(
            f'{path.name}: the first line must be "# v{version}" or "# v{version}（summary）", '
            f'found {first_line!r}')
    return Entry(version=version, summary=(heading['summary'] or '').strip())


def collect(releases: pathlib.Path) -> list[Entry]:
    entries = []
    for path in releases.iterdir():
        name = NOTE_NAME.fullmatch(path.name)
        if name and path.is_file():
            entries.append(read_entry(path, name[1]))
    return sorted(entries, key=lambda entry: entry.key)


def link(entry: Entry) -> str:
    summary = f'（{entry.summary}）' if entry.summary else ''
    return f'- [v{entry.version} のリリースノート{summary}]({RELEASES_LINK}v{entry.version}.md)'


def render(releases: pathlib.Path) -> list[str]:
    if not (releases / UNRELEASED_FILE).is_file():
        raise ReleaseNotesError(f'{RELEASES_DIR}/{UNRELEASED_FILE} is missing')
    lines = [link(entry) for entry in collect(releases)]
    lines.append(f'- [未リリースの変更]({RELEASES_LINK}{UNRELEASED_FILE})')
    return lines


def split_block(text: str) -> tuple[str, list[str], str]:
    """Return the text up to the begin marker line, the lines inside, and the rest."""
    lines = text.splitlines(keepends=True)
    positions = {}
    for marker in (BEGIN_MARKER, END_MARKER):
        found = [number for number, line in enumerate(lines) if line.strip() == marker]
        if len(found) != 1:
            state = 'missing' if not found else f'found {len(found)} times'
            raise ReleaseNotesError(f'{INDEX_FILE}: marker {marker} must appear once on its own line ({state})')
        positions[marker] = found[0]
    begin, end = positions[BEGIN_MARKER], positions[END_MARKER]
    if begin > end:
        raise ReleaseNotesError(f'{INDEX_FILE}: marker {BEGIN_MARKER} must come before {END_MARKER}')
    inner = [line.rstrip('\n') for line in lines[begin + 1:end]]
    return ''.join(lines[:begin + 1]), inner, ''.join(lines[end:])


def run(root: pathlib.Path, check: bool) -> int:
    index = root / INDEX_FILE
    head, current, tail = split_block(index.read_text(encoding='utf-8'))
    expected = render(root / RELEASES_DIR)
    if current == expected:
        print(f'{INDEX_FILE}: the release notes list is up to date.')
        return 0
    if check:
        print(f'error: {INDEX_FILE}: the release notes list is out of date.', file=sys.stderr)
        diff = difflib.unified_diff(current, expected, 'current', 'expected', lineterm='')
        for line in diff:
            print(line, file=sys.stderr)
        print(f'Run `{REGENERATE_COMMAND}` and commit the result.', file=sys.stderr)
        return 1
    index.write_text(head + ''.join(line + '\n' for line in expected) + tail, encoding='utf-8')
    print(f'{INDEX_FILE}: updated the release notes list.')
    return 0


def main(argv: list[str] | None = None, root: pathlib.Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true',
                        help='do not write; exit 1 with a diff when the index is out of date')
    args = parser.parse_args(argv)
    try:
        return run(root, args.check)
    except (ReleaseNotesError, OSError, UnicodeDecodeError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
