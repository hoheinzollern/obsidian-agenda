# Obsidian Agenda

A minimal, org-agenda–style dashboard for tasks stored in an [Obsidian](https://obsidian.md) vault using the [Obsidian Tasks](https://publish.obsidian.md/tasks/Introduction) plugin format. Runs on **macOS** and **Android**, reads the markdown files directly off disk, and writes check-offs back in-place.

Why exists: agenda views inside Obsidian work great on desktop but feel sluggish on mobile, and the existing mobile Tasks views don't compose the way `org-agenda` does. This is a fast, focused dashboard you can pin on your phone or open on your Mac for the same source of truth.

## Features

- **Sectioned dashboard**: Overdue · Today · This week · Next 30 days · Floating (no date).
- **Read/write to markdown**: tap the status indicator to flip `- [ ]` ↔ `- [x]` (with `✅ YYYY-MM-DD` stamp). Long-press / right-click to pick any of the four states — `TODO` / `WAIT` / `DONE` / `CANCELLED` (cancelled gets `❌ YYYY-MM-DD`). Sections collapse and re-open, state persists.
- **Open in Obsidian**: tap a task card → opens that note via `obsidian://open`. With the [Advanced URI](https://github.com/Vinzent03/obsidian-advanced-uri) community plugin installed and the matching toggle enabled in Settings, it jumps to the exact line.
- **Quick nav**: anchor chips at the bottom of the dashboard plus `⌘1`–`⌘5` (macOS) / `Ctrl+1`–`5` to jump to any section.
- **Theme-aware**: light + dark mode with per-section color palettes that stay legible in either.
- **Local-only**: no servers, no telemetry. The app reads files on the same device it runs on.

## Supported syntax

```
- [ ] Reply to Alice 📅 2026-05-19 #admin ⏫
- [x] Conference registration #admin ✅ 2026-05-21
- [ ] Step 0 — planning ⏳ 2026-08-10 #hop
```

| Marker | Meaning |
|---|---|
| `- [ ]` | open task |
| `- [x]` | done |
| `- [/]` | in progress |
| `- [-]` | cancelled |
| 📅 | due date (DEADLINE) |
| ⏳ | scheduled date |
| 🛫 | start date |
| ✅ | done date |
| ❌ | cancelled date |
| 🔺 ⏫ 🔼 🔽 🔻 | priority (highest → lowest) |
| `#tag` | tag |
| `[[wiki\|display]]` | wiki link (display text kept) |

## Install

### Releases (recommended)

Each tagged release on this repo ships pre-built artifacts:

- **Android**: download `obsidian-agenda-vX.Y.Z.apk` from the [latest release](https://github.com/hoheinzollern/obsidian-agenda/releases) and sideload (`adb install` or copy to phone + tap).
- **macOS**: download `obsidian-agenda-vX.Y.Z-macos.zip`, unzip, drag to Applications. The build is unsigned, so the first launch needs **right-click → Open** to bypass Gatekeeper.
- **Linux (x64)**: download `obsidian-agenda-vX.Y.Z-linux-x64.tar.gz`, extract anywhere, and run `./obsidian-agenda`. Built against GTK 3 / Ubuntu 22.04.
- **Windows (x64)**: download `obsidian-agenda-vX.Y.Z-windows-x64.zip`, extract, and run `obsidian-agenda.exe`. Unsigned, so SmartScreen may warn on first launch — click **More info → Run anyway**.

### From source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.22+ and the Android SDK / Xcode depending on target.

```sh
git clone https://github.com/hoheinzollern/obsidian-agenda
cd obsidian-agenda
flutter pub get

# Android (requires Android SDK 36 + build-tools)
flutter build apk --release

# macOS (requires Xcode)
flutter build macos --release
open build/macos/Build/Products/Release/obsidian-agenda.app
```

## First run

1. App opens to "No vault selected". Tap **Pick vault folder**.
2. On macOS, click the folder icon next to the path field to open a native folder picker. On Android, type the absolute path (e.g. `/storage/emulated/0/obsidian-experiment` — wherever Syncthing / Obsidian Sync drops your vault).
3. Grant **All files access** when prompted on Android (needed to read/write arbitrary folders).
4. Dashboard renders. Pull to refresh.

## CLI

The same parser + writer logic that powers the apps is exposed as a Dart
CLI. Useful for scripting (cron jobs, shell aliases, status-bar widgets).

### Install

```sh
./install.sh                          # → ~/.local/bin/agenda
PREFIX=/usr/local/bin sudo ./install.sh
./install.sh --uninstall              # removes the binary
```

The script needs Flutter on PATH (the project's pubspec depends on
Flutter packages). It runs `flutter pub get` and `dart compile exe`,
then copies the binary into the install prefix.

### Configure

The CLI stores its config in `~/.config/obsidian-agenda/config` (or
`$XDG_CONFIG_HOME/obsidian-agenda/config`). Set the vault once:

```sh
agenda config set vault /path/to/your/obsidian/vault
agenda config show
agenda config path
```

Vault resolution order: `--vault` flag → `$OBSIDIAN_AGENDA_VAULT` env →
config file → error.

### Use

```sh
agenda today                                # bucket → list
agenda overdue
agenda list week --tag admin
agenda list --count overdue                 # just the number
agenda add "Pay phone bill" --due 2026-05-25 --tag admin --prio high
agenda done areas/admin.md:9                # toggle a specific task
agenda wait projects/foo.md:42              # set to in-progress
agenda scan                                 # vault summary
```

Subcommands:

| Command | Description |
|---|---|
| `list [bucket]` | `overdue` / `today` / `week` / `next30` / `floating` / `all`. Default `today`. Supports `--tag`, `--folder`, `--count`. |
| `today`, `overdue`, `week`, `next30`, `floating` | Shortcuts for `list <bucket>`. |
| `add <description...>` | Append to `<vault>/inbox.md`. `--due YYYY-MM-DD`, `--prio {highest,high,medium,low,lowest,none}`, `--tag X` (repeatable). |
| `done`, `cancel`, `wait`, `todo` | Set a task's status, identified by `<file>:<line>` (line number 1-based). |
| `config {get,set,show,path}` | Read or write the stored config. |
| `scan` | Vault summary — files, totals, parse errors. |

ANSI colour is on when stdout is a TTY; disable with `--no-color` or
`NO_COLOR=1`.

## Architecture

```
lib/
├── main.dart                       Material 3 app, light+dark
├── models/task.dart                Task + TaskStatus + TaskPriority enums
├── parser/gtd_parser.dart          Line-level markdown parser
├── services/
│   ├── settings_service.dart       Persists vault path, Advanced URI toggle, collapsed sections
│   ├── vault_service.dart          Recursive .md scan (skips .obsidian/, .trash/, templates/)
│   ├── task_writer.dart            In-place toggle on the source file; bails safely if file drifted
│   └── obsidian_launcher.dart      Builds obsidian:// URIs (built-in and Advanced URI)
├── widgets/task_card.dart          Card with checkbox + chips + priority + source label
└── screens/
    ├── dashboard_screen.dart       Sections, anchor bar, keyboard shortcuts
    └── settings_screen.dart        Vault picker + Advanced URI toggle
```

Tests live in `test/` (parser, writer, widget smoke). Run with `flutter test`.

## Sync strategy

This app doesn't sync — it just reads/writes files already on the device. Pair it with whichever sync you already use:

- **Syncthing** — folder-level sync between machine and phone. Recommended.
- **Obsidian Sync** — if you use Obsidian mobile, vault is already there.
- **Termux + `git pull`** — manual but works.

## Known limitations

- No "create task" UI yet — only check-off is implemented.
- No editing of due dates, priority, or description in-app.
- Android requires `MANAGE_EXTERNAL_STORAGE`, which Google Play would reject without justification. Fine for personal sideloading and F-Droid-style distribution.
- macOS builds are unsigned; first launch needs right-click → Open.

## License

[MIT](./LICENSE) — © 2026 Alessandro Bruni.
