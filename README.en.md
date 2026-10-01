# openpath

[日本語](README.md) | English

[![CI](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

openpath is a macOS menu bar app that overlays a `cdr`/`fzf`-style fuzzy finder
on top of the system file dialog (NSOpenPanel). In any app's "Open Folder" or
"Attach File" dialog, including Claude Desktop, Cursor, VS Code, and browsers,
you type a few characters and press Return instead of walking the Finder tree.

The first stable release, `v0.1.0`, is in preparation and has not been
published on GitHub Releases yet. Until then, [build it from source](#build-from-source).
openpath asks only for the Accessibility permission and never uses the network.

The user interface is Japanese only. The design documents under `docs/` and the
community files are written in Japanese; this English README covers installation
and everyday use.

## Find what you need

| Goal | Section |
| --- | --- |
| Learn what it does | [Features](#features), [How it works](#how-it-works) |
| Install it | [Install](#install) |
| Learn the keys | [Usage](#usage) |
| Change candidate sources or the hotkey | [Configuration](#configuration) |
| Review permissions and data handling | [Permissions](#permissions), [Privacy](#privacy) |
| Diagnose a problem | [Troubleshooting](#troubleshooting) |
| Contribute | [Development](#development), [Contributing](#contributing) |

## Features

- **Appears on its own**: when a file dialog opens, the palette overlays it
  automatically. The hotkey (Ctrl+Shift+O by default) only re-opens a palette
  you closed.
- **Terminal muscle memory**: choose with ↑↓ or Ctrl+N / Ctrl+P, move with
  Return, and drill into subdirectories with Tab.
- **Frequent places first**: confirmed paths are ranked by frecency (use count
  and recency). Repositories from [ghq](https://github.com/x-motemen/ghq) and
  directories under your configured `roots` are candidates too.
- **Does not replace the dialog**: press Esc and the original dialog is still
  there.
- **You confirm**: by default openpath only navigates the dialog; you press
  "Open" yourself. Cmd+Return navigates and opens in one step.
- **Non-ASCII paths**: the path is pasted through the clipboard, so Japanese
  folder names are entered intact. See [Privacy](#privacy) for how the
  clipboard is handled.

## How it works

1. The Accessibility API detects a file dialog (NSOpenPanel) in the frontmost
   app. Save dialogs are ignored.
2. The palette is placed over the dialog's top-right corner without taking
   focus from the dialog.
3. Candidates from history, ghq, and `roots` are fuzzy-matched as you type.
4. The chosen path is entered through "Go to Folder" (⌘⇧G).

## Install

openpath runs on macOS 14 (Sonoma) or later, on Apple Silicon and Intel.

### ZIP from GitHub Releases

Builds are published on [GitHub Releases](https://github.com/TamaT-LLC/openpath/releases).
The first preview, `preview-v0.1.0-1`, and the first stable release, `v0.1.0`,
are not published yet.

| Channel | Tag | Signing | Intended use |
| --- | --- | --- | --- |
| Stable | `vX.Y.Z` | Developer ID signed and notarized by Apple | Everyday use |
| Preview | `preview-vX.Y.Z-N` | Ad-hoc signed, not notarized | Pre-release evaluation |

The ZIP is a Universal build for Apple Silicon and Intel. Save every asset of a
release in one directory, verify the checksums, then extract the ZIP:

```bash
shasum -a 256 --check SHA256SUMS
```

Move `openpath.app` to Applications and open it. Previews are not notarized,
so Gatekeeper blocks the first launch; allow it from System Settings > Privacy &
Security only if you intend to evaluate the preview.

### Homebrew cask

Each stable release includes a Homebrew cask (`openpath.rb`) for that exact
ZIP. Installation from a Homebrew tap will be documented here after the first
stable release.

### Build from source

The Command Line Tools (`xcode-select --install`) and a Swift 6.0 or later
toolchain are enough; Xcode is not required.

```bash
git clone https://github.com/TamaT-LLC/openpath.git
cd openpath
./scripts/build.sh        # assemble build/openpath.app (Universal 2)
./scripts/sign.sh         # ad-hoc signing unless OPENPATH_SIGN_IDENTITY is set
open build/openpath.app   # runs in the menu bar, not in the Dock
```

An ad-hoc signature changes on every rebuild, so macOS treats the rebuilt app
as a different program. After rebuilding, remove openpath from System Settings >
Privacy & Security > Accessibility and add it again. A Developer ID signed app
keeps the permission across updates.

## Usage

### First launch

The first launch opens a guide: why the Accessibility permission is needed,
granting it in System Settings, and a "Try it" step that opens a folder dialog
so you can see the palette (the chosen folder is not used). The guide is shown
once; reopen it any time from the menu bar item "はじめに…" (Getting started).

If `~/.config/openpath/config.toml` does not exist at launch, openpath creates
it with the default values (see [Configuration](#configuration)).

### Palette keys

| Key | Action |
| --- | --- |
| Typing | Fuzzy-search candidates. Matching waits while an input method is composing |
| ↑ / ↓, Ctrl+P / Ctrl+N | Choose a candidate |
| Return | Navigate the dialog to the candidate. With `auto_confirm = true`, also press "Open" |
| Cmd+Return | Navigate and press "Open" |
| Tab | Expand the candidate's path into the search field to narrow down subdirectories |
| Cmd+Z | Undo a Tab expansion |
| Esc | Close the palette; the dialog stays usable |
| Ctrl+Shift+O | Re-open the palette (configurable) |

Typing a path that starts with `/` or `~/` shows that path as the first
candidate when it exists, and Return navigates to it directly.

### Menu bar

The menu bar item offers: enable/disable detection ("有効"), rebuild candidates
("候補を再構築"; also runs every five minutes), open the configuration file
("設定ファイルを開く…", ⌘,), clear history ("履歴をクリア…"), launch at login
("ログイン時に起動"; only when started as `openpath.app`), and the first-launch
guide ("はじめに…"). A badge on the icon signals a missing permission or a
configuration error, and the first menu item explains how to fix it.

## Configuration

Settings live in `~/.config/openpath/config.toml` (TOML). openpath reloads the
file when it is saved; if the file has an error, the previous settings stay in
effect.

| Key | Value written on first launch | Meaning |
| --- | --- | --- |
| `roots` | The ghq root, or `["~"]` without ghq | Directories to scan for candidates. `~` is your home directory |
| `depth` | `2` | Scan depth under each root (0 or more) |
| `include_files` | `false` | Include files as well as directories when the dialog type cannot be inferred |
| `auto_confirm` | `false` | Press "Open" automatically after navigating |
| `hotkey` | `"ctrl+shift+o"` | Hotkey that re-opens the palette: modifiers (`ctrl`, `opt`, `shift`, `cmd`) and a key joined by `+` |
| `disabled_apps` | `[]` | Bundle IDs of apps where the palette never appears (for example `["com.apple.finder"]`) |
| `ignore` | `["node_modules", ".git", "target", "DerivedData", ".build"]` | Directory names skipped while scanning |
| `enabled` in `[ghq]` | `true` | Include repositories listed by `ghq list -p` |

The initial `roots` depends on your environment at first launch: the ghq root
when `ghq root` resolves to an absolute path, otherwise your home directory
(`["~"]`). Scanning your whole home directory yields many candidates, so
consider narrowing `roots` to the directories you use most, for example
`roots = ["~/repos", "~/Documents"]`. openpath never overwrites an existing
file.

## Permissions

openpath asks only for the Accessibility permission, which it uses to detect
file dialogs and to enter paths. Grant it in System Settings > Privacy &
Security > Accessibility. Without it, detection stops and the menu bar icon
shows a badge. Full Disk Access is not required.

If `roots` includes Desktop, Documents, or Downloads (for example the home
directory, which is the default without ghq), macOS may ask for access the first
time openpath reads inside those folders. The prompt explains that openpath
reads item names to offer them as candidates. Denying access only removes those
folders' contents from the candidates. You can change the decision later in
System Settings > Privacy & Security > Files and Folders, then choose
"候補を再構築" (rebuild candidates) from the menu.

## Privacy

- openpath makes no network connections and depends on no external service.
- It reads only the part of the frontmost app's window hierarchy needed to
  recognize a file dialog. Window contents and typed values are not stored.
- The clipboard is used briefly to paste the path, and its previous contents
  are restored afterwards. Contents marked as concealed
  (`org.nspasteboard.ConcealedType`, used by password managers) are not saved;
  the clipboard is cleared after the path is entered instead. If something new
  is copied while the path is being entered, that new content is kept.
- Stored data: configuration (`~/.config/openpath/config.toml`), confirmed-path
  history (`~/Library/Application Support/openpath/history.json`), and logs
  (`~/Library/Logs/openpath/`). None of it leaves your Mac.
- Logs at info level and above contain no paths or file names; paths are
  recorded only at debug level.

See [SECURITY.md](SECURITY.md) (Japanese) for the vulnerability reporting route
and scope.

## Troubleshooting

- If the palette does not appear, check that "有効" (enabled) is checked in the
  menu, that the Accessibility permission is granted, and that the app is not
  in `disabled_apps`. After closing the palette with Esc, Ctrl+Shift+O brings it
  back.
- To restart the first-launch guide, quit openpath and run
  `defaults delete jp.tamat.openpath onboardingFinished`.

Logs are written to `~/Library/Logs/openpath/openpath.log` (rotated to
`openpath.log.1` above 5 MiB) and to the unified log (subsystem
`jp.tamat.openpath`). To capture a debug log, quit openpath, run the command
below, start openpath again, and reproduce the problem:

```bash
defaults write jp.tamat.openpath logLevel debug
```

Debug logs contain paths in plain text. Redact paths and user names before
sharing them, and restore the default level afterwards (quit openpath first):

```bash
defaults delete jp.tamat.openpath logLevel
```

## Development

```bash
swift build          # build
./scripts/test.sh    # unit tests (Swift Testing); `swift test` also works with Xcode
swift run openpath   # run from source
```

With only the Command Line Tools, plain `swift test` fails with
`no such module 'Testing'`; `scripts/test.sh` adds the required flags and passes
its arguments to `swift test`. Behavior that depends on the Accessibility API
and synthesized key events cannot run in CI and is covered by the manual
scenarios in `docs/50_test/test-openpath-manual-scenarios.md`.

Releases are cut by maintainers through the `Release macOS` GitHub Actions
workflow (Smoke, Preview, and Stable channels). The procedure is documented in
Japanese in [docs/40_arch_design/guide-release-distribution.md](docs/40_arch_design/guide-release-distribution.md),
and the required secrets are listed in the [Japanese README](README.md#github-actions-でリリースする).

## Contributing

Issues and pull requests are welcome, including ones written in English. Read
[CONTRIBUTING.md](CONTRIBUTING.md) (Japanese) first. Support
policy: [SUPPORT.md](SUPPORT.md). Governance: [GOVERNANCE.md](GOVERNANCE.md).
Everyone is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Do not report suspected vulnerabilities in a public issue; use the
[private vulnerability report](https://github.com/TamaT-LLC/openpath/security/advisories/new)
described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)

Copyright (c) 2026 TamaT LLC.
