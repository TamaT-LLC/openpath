#!/usr/bin/env python3
"""Publish validated assets through a draft; never overwrite an existing release."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile
from release_metadata import parse_tag


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def validate_assets(directory, channel, version, preview):
    suffix = '' if channel == 'stable' else '-preview.' + preview
    names = ['openpath-' + version + suffix + '.zip']
    if channel == 'stable':
        names.append('openpath.rb')
    expected = sorted(names + ['SHA256SUMS'])
    if sorted(p.name for p in directory.iterdir()) != expected:
        raise ValueError('release assets are missing or unexpected files are present')
    if any(p.is_symlink() or not p.is_file() or p.stat().st_size == 0 for p in directory.iterdir()):
        raise ValueError('release assets must be nonempty regular files')
    checksums = ''.join(hashlib.sha256((directory / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names)
    if (directory / 'SHA256SUMS').read_text() != checksums:
        raise ValueError('SHA256SUMS does not match release assets')
    return expected


def verify_uploaded(release, names, draft, prerelease=None):
    if release['isDraft'] != draft or sorted(a['name'] for a in release['assets']) != names:
        raise ValueError('uploaded release state or assets differ; inspect the release before retrying')
    if prerelease is not None and release['isPrerelease'] != prerelease:
        raise ValueError('unexpected prerelease state')


def publish(repo, tag, directory):
    channel, version, preview = parse_tag(tag)
    names = validate_assets(directory, channel, version, preview)
    existing = gh('api', f'repos/{repo}/releases', '--paginate', '--jq', '.[].tag_name').splitlines()
    if tag in existing:
        raise ValueError('release already exists; it will not be overwritten')
    is_preview = channel == 'preview'
    title = f'openpath {version}' + (f' Preview {preview}' if is_preview else '')
    notes = ('This preview uses ad-hoc signing and is not notarized by Apple. '
             'It is for testing and does not replace the stable release.\n\n' if is_preview else
             'Developer ID signed and notarized by Apple.\n\n')
    notes += ('macOS 14 or later; Universal ZIP for Apple Silicon and Intel.\n'
              'Verify with `shasum -a 256 --check SHA256SUMS`, then extract the ZIP '
              'and move `openpath.app` to Applications.\n')
    if not is_preview:
        notes += '\n`openpath.rb` is the Homebrew cask for this exact ZIP.\n'
    with tempfile.TemporaryDirectory(prefix='openpath-release-') as temp:
        note_file = pathlib.Path(temp) / 'notes.md'
        note_file.write_text(notes)
        gh('release', 'create', tag, '--repo', repo, '--verify-tag', '--draft',
           '--title', title, '--notes-file', str(note_file), '--generate-notes',
           *[str(directory / name) for name in names])
    fields = 'isDraft,isPrerelease,assets'
    verify_uploaded(json.loads(gh('release', 'view', tag, '--repo', repo, '--json', fields)), names, True)
    gh('release', 'edit', tag, '--repo', repo, '--draft=false',
       '--prerelease=' + str(is_preview).lower(), '--latest=' + str(not is_preview).lower())
    verify_uploaded(json.loads(gh('release', 'view', tag, '--repo', repo, '--json', fields)), names, False, is_preview)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        publish(args.repo, args.tag, args.directory)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'error: release publication failed: {error}\n')


if __name__ == '__main__':
    main()
