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

chmod +x "$REPO/panopticon.sh" "$REPO/sleep.sh" "$REPO/wake.sh"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.panopticon"

ln -sfn "$PLIST_SRC" "$PLIST_DST"
echo "symlinked $PLIST_DST -> $PLIST_SRC"

# Sleep/wake hooks via sleepwatcher. We refuse to clobber existing hook files
# the user may already be using for unrelated purposes.
install_hook() {
    local src=$1 dst=$2
    if [[ -L "$dst" ]]; then
        if [[ "$(readlink "$dst")" == "$src" ]]; then
            return 0  # already correct
        fi
        echo "warning: $dst is a symlink to $(readlink "$dst"); not overwriting" >&2
        echo "         add this line to it manually if you want panopticon hooks:" >&2
        echo "         $src" >&2
        return 1
    fi
    if [[ -e "$dst" ]]; then
        echo "warning: $dst exists (not a symlink); not overwriting" >&2
        echo "         add the contents of $src to it manually" >&2
        return 1
    fi
    ln -s "$src" "$dst"
    echo "symlinked $dst -> $src"
}

if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx sleepwatcher; then
    install_hook "$REPO/sleep.sh" "$HOME/.sleep" || true
    install_hook "$REPO/wake.sh" "$HOME/.wakeup" || true
    if ! brew services list 2>/dev/null | awk '$1=="sleepwatcher" && $2=="started" {found=1} END {exit !found}'; then
        brew services start sleepwatcher
    fi
else
    echo "note: install sleepwatcher (brew install sleepwatcher) and re-run for sleep/wake-aware rotation"
fi

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
