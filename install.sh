#!/usr/bin/env bash
# Compile the `agenda` CLI from this checkout and install it under
# ~/.local/bin (override with PREFIX=...). Requires the Flutter SDK on
# PATH (the project's pubspec pulls Flutter packages).
#
# Usage:
#   ./install.sh               # -> ~/.local/bin/agenda
#   PREFIX=/usr/local/bin sudo ./install.sh
#   ./install.sh --uninstall   # removes the installed binary

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PREFIX="${PREFIX:-$HOME/.local/bin}"
TARGET="$PREFIX/agenda"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -f "$TARGET" ]]; then
    rm "$TARGET"
    green "[ok] Removed $TARGET"
  else
    yellow "(nothing at $TARGET)"
  fi
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  red "error: 'flutter' not found on PATH."
  red "       The project's pubspec depends on Flutter packages; install"
  red "       the Flutter SDK (https://docs.flutter.dev/get-started/install)"
  red "       and try again."
  exit 1
fi

bold "Resolving Dart dependencies..."
( cd "$SCRIPT_DIR" && flutter pub get >/dev/null )

bold "Compiling tool/agenda.dart -> native binary..."
mkdir -p "$SCRIPT_DIR/build/cli"
( cd "$SCRIPT_DIR" && dart compile exe tool/agenda.dart \
    -o "$SCRIPT_DIR/build/cli/agenda" >/dev/null )

bold "Installing into $PREFIX..."
mkdir -p "$PREFIX"
install -m 0755 "$SCRIPT_DIR/build/cli/agenda" "$TARGET"
green "[ok] Installed $TARGET"

# PATH hint.
if ! printf '%s' ":$PATH:" | grep -q ":$PREFIX:"; then
  echo
  yellow "!  $PREFIX is not on your PATH. Add this to your shell rc:"
  echo "    export PATH=\"$PREFIX:\$PATH\""
fi

echo
bold "Next steps"
echo "  agenda config set vault /path/to/your/obsidian/vault"
echo "  agenda today"
echo "  agenda add \"Pay phone bill\" --due 2026-05-25 --tag admin"
