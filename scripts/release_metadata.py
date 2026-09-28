#!/usr/bin/env python3
"""Validate release refs before any job receives signing credentials."""
import argparse
import plistlib
import re
import subprocess

VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE).decode().strip()


def parse_tag(tag):
    stable = re.fullmatch(r'v(' + VERSION + ')', tag)
    preview = re.fullmatch(r'preview-v(' + VERSION + r')-([1-9][0-9]*)', tag)
    if stable:
        return 'stable', stable[1], ''
    if preview:
        return 'preview', preview[1], preview[2]
    raise ValueError('tag must be vX.Y.Z or preview-vX.Y.Z-N without leading zeroes')


def metadata(tag=None, main_ref='refs/remotes/origin/main'):
    commit = git('rev-parse', 'HEAD')
    version = plistlib.loads(git('show', commit + ':Resources/Info.plist').encode())['CFBundleShortVersionString']
    if not re.fullmatch(VERSION, version):
        raise ValueError('Info.plist version must be X.Y.Z without leading zeroes')
    app_info = git('show', commit + ':Sources/OpenPathCore/AppInfo.swift')
    app_version = re.search(r'static\s+let\s+version\s*=\s*"([^"]+)"', app_info)
    if not app_version or app_version[1] != version:
        raise ValueError('AppInfo.swift and Info.plist versions differ')
    channel, preview = 'smoke', ''
    if tag:
        channel, tag_version, preview = parse_tag(tag)
        ref = 'refs/tags/' + tag
        if git('cat-file', '-t', ref) != 'tag':
            raise ValueError('release tag must be annotated')
        if git('rev-parse', ref + '^{commit}') != commit:
            raise ValueError('checkout must match the release tag commit')
        git('merge-base', '--is-ancestor', commit, main_ref)
        if tag_version != version:
            raise ValueError('tag version does not match Info.plist')
    suffix = '' if channel == 'stable' else ('-smoke' if channel == 'smoke' else '-preview.' + preview)
    return dict(channel=channel, version=version, preview_number=preview,
                commit=commit, asset_name='openpath-' + version + suffix + '.zip')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--tag')
    mode.add_argument('--smoke', action='store_true')
    parser.add_argument('--main-ref', default='refs/remotes/origin/main')
    args = parser.parse_args()
    try:
        for key, value in metadata(args.tag, args.main_ref).items():
            print(f'{key}={value}')
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'error: release metadata validation failed: {error}\n')


if __name__ == '__main__':
    main()
