#!/usr/bin/env bash
# Sleepwatcher hook: stop panopticon before system sleep so the current
# segment flushes cleanly (rather than being suspended mid-encode).
launchctl bootout "gui/$(id -u)/local.panopticon" 2>/dev/null || true
