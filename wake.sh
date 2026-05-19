#!/usr/bin/env bash
# Sleepwatcher hook: restart panopticon after wake, starting a fresh segment.
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.panopticon.plist"
