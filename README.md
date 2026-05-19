# panopticon

Continuous screen recording of every attached display, hourly mkv segments, runs as a per-user launchd agent on macOS.

## Layout

```
~/.panopticon/
├── panopticon.log         # stdout (one line per agent start: discovered screens)
├── panopticon.err         # ffmpeg stderr
└── 2026-05-18/
    ├── screen-0/
    │   └── 16-08-43.mkv   # one segment per hour, named by start time
    └── screen-1/
        └── 16-08-43.mkv
```

Override the root dir with `PANOPTICON_ROOT` in the plist's `EnvironmentVariables` if you don't want `~/.panopticon`. Screen indices are renormalized to `screen-0, screen-1, ...` so adding/removing cameras doesn't shuffle the layout.

## Requirements

- Homebrew bash (`brew install bash`) — the script uses `wait -n` and other bash 4+ features; system bash 3.2 is too old.
- ffmpeg with libx265 (`brew install ffmpeg`).
- An mkv-capable player for review (e.g. `brew install --cask iina` or `vlc`). QuickTime/Preview won't open `.mkv`.

## Install

```sh
./install.sh
```

This symlinks `local.panopticon.plist` into `~/Library/LaunchAgents/` and bootstraps the agent. First run will prompt for **Screen Recording** permission. If frames aren't being captured (`panopticon.err` shows "Configuration of video device failed" but no encoding progress), open System Settings → Privacy & Security → Screen & System Audio Recording and enable both `/opt/homebrew/bin/bash` and `/opt/homebrew/bin/ffmpeg`, then:

```sh
launchctl kickstart -k gui/$(id -u)/local.panopticon
```

## Managing the agent

```sh
# status
launchctl print gui/$(id -u)/local.panopticon

# restart (e.g. after editing the script)
launchctl kickstart -k gui/$(id -u)/local.panopticon

# stop until next login
launchctl bootout gui/$(id -u)/local.panopticon

# stop now and forever
launchctl bootout gui/$(id -u)/local.panopticon
rm ~/Library/LaunchAgents/local.panopticon.plist
```

## Files

- `panopticon.sh` — the recorder; discovers displays, spawns one ffmpeg per display, manages hourly rotation, handles signal-translation cleanup (launchd SIGTERM → SIGINT to ffmpeg, then SIGKILL after 5s).
- `local.panopticon.plist` — the launchd agent definition. Symlinked into `~/Library/LaunchAgents/` by `install.sh`.
- `install.sh` — bootstraps the agent.

## Notes on the design

Segments are written as **mkv**. It's robust to truncation: even if ffmpeg crashes or is hard-killed mid-recording, the in-progress file is still readable up to the last flushed cluster. mp4 would need to be either fragmented (which breaks time-based seeking under our config) or finalized cleanly with a tail moov (which we lose on crash).

Hourly rotation is **bash-managed**, not via ffmpeg's `-f segment` muxer. The segment muxer mis-tracks PTS when combined with fragmented inner formats, and ffmpeg's PTS clock advances slowly when AVFoundation's source is mostly idle (display sleep), so neither `-segment_time` nor `-t` reliably triggers on wall time. Instead the script runs one ffmpeg per screen in parallel, with a `sleep 3600 &` watchdog; whichever wakes first (the timer, or any ffmpeg dying) tears the batch down and the loop restarts with fresh filenames.

ffmpeg on macOS AVFoundation **ignores SIGTERM** — the script sends SIGINT on shutdown instead, then escalates to SIGKILL after a short grace period. This is why `panopticon.sh` is bash, not just an ffmpeg invocation: it needs to translate launchd's SIGTERM into something ffmpeg actually responds to.
