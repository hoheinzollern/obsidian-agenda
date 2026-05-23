#!/usr/bin/env bash
# Install (or uninstall) the pre-built obsidian-agenda Linux bundle.
#
# Run this script from inside the extracted release archive:
#
#   ./install.sh              # installs for the current user
#   sudo ./install.sh         # installs system-wide under /opt + /usr/local
#   ./install.sh --uninstall  # removes a user install
#   sudo ./install.sh --uninstall  # removes a system-wide install

set -euo pipefail

BUNDLE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="obsidian-agenda"

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# Pick install prefix based on whether we are root.
if [[ "$EUID" -eq 0 ]]; then
  INSTALL_DIR="/opt/$APP_NAME"
  BIN_DIR="/usr/local/bin"
  DESKTOP_DIR="/usr/share/applications"
else
  INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
  BIN_DIR="${HOME}/.local/bin"
  DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
fi

WRAPPER="$BIN_DIR/$APP_NAME"
DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"

# ── uninstall ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  removed=0
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    green "[ok] Removed $INSTALL_DIR"
    removed=1
  fi
  if [[ -f "$WRAPPER" ]]; then
    rm "$WRAPPER"
    green "[ok] Removed $WRAPPER"
    removed=1
  fi
  if [[ -f "$DESKTOP_FILE" ]]; then
    rm "$DESKTOP_FILE"
    green "[ok] Removed $DESKTOP_FILE"
    removed=1
  fi
  if [[ "$removed" -eq 0 ]]; then
    yellow "(nothing installed at the expected locations)"
  fi
  exit 0
fi

# ── sanity-check the bundle ───────────────────────────────────────────────────
if [[ ! -f "$BUNDLE_DIR/$APP_NAME" ]]; then
  red "error: '$APP_NAME' binary not found in $BUNDLE_DIR"
  red "       Run this script from inside the extracted release archive."
  exit 1
fi

# ── install ───────────────────────────────────────────────────────────────────
bold "Installing bundle to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp -a "$BUNDLE_DIR/." "$INSTALL_DIR/"
chmod 0755 "$INSTALL_DIR/$APP_NAME"

bold "Creating launcher wrapper at $WRAPPER ..."
mkdir -p "$BIN_DIR"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/$APP_NAME" "\$@"
EOF
chmod 0755 "$WRAPPER"

bold "Installing .desktop entry ..."
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Obsidian Agenda
Comment=Org-agenda-style dashboard for your Obsidian vault
Exec=$INSTALL_DIR/$APP_NAME
Icon=$INSTALL_DIR/data/flutter_assets/assets/icon/icon.png
Terminal=false
Categories=Utility;Office;
StartupWMClass=obsidian-agenda
EOF

green "[ok] Installed $APP_NAME"

# PATH hint for non-root installs.
if [[ "$EUID" -ne 0 ]] && ! printf '%s' ":$PATH:" | grep -q ":$BIN_DIR:"; then
  echo
  yellow "!  $BIN_DIR is not on your PATH. Add this to your shell rc:"
  echo "    export PATH=\"$BIN_DIR:\$PATH\""
fi

echo
bold "Launch the app:"
echo "  $APP_NAME"
echo "  # or open 'Obsidian Agenda' from your desktop application menu"
