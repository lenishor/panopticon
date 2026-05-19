#!/usr/bin/env bash
# Install panopticon as a per-user launchd agent.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC="$REPO/local.panopticon.plist"
PLIST_DST="$HOME/Library/LaunchAgents/local.panopticon.plist"
LABEL="local.panopticon"
DOMAIN="gui/$(id -u)"

need() {
    command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }
}
need ffmpeg
need /opt/homebrew/bin/bash

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    echo "stopping existing agent"
    launchctl bootout "$DOMAIN/$LABEL"
fi

chmod +x "$REPO/panopticon.sh"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.panopticon"

ln -sfn "$PLIST_SRC" "$PLIST_DST"
echo "symlinked $PLIST_DST -> $PLIST_SRC"

launchctl bootstrap "$DOMAIN" "$PLIST_DST"
echo "agent bootstrapped"

cat <<'EOF'

First-run note: macOS will prompt for Screen Recording permission for bash
(and possibly ffmpeg) the first time the agent tries to capture. If you
don't see frames being written to ~/.panopticon/<date>/screen-*/, open
System Settings -> Privacy & Security -> Screen & System Audio Recording
and ensure both /opt/homebrew/bin/bash and /opt/homebrew/bin/ffmpeg are
enabled, then run: launchctl kickstart -k gui/$(id -u)/local.panopticon
EOF
