#!/opt/homebrew/bin/bash
# panopticon: continuous screen recording of all attached displays

set -uo pipefail

root="${PANOPTICON_ROOT:-$HOME/.panopticon}"
segment_seconds=3600

# ffmpeg writes the device list to stderr and exits nonzero (no input file).
# Both are expected.
discover_screens() {
    ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
        | sed -nE 's/.*\[([0-9]+)\] Capture screen [0-9]+.*/\1/p'
}

screens=()
while IFS= read -r line; do
    screens+=("$line")
done < <(discover_screens)

if (( ${#screens[@]} == 0 )); then
    echo "no screen capture devices found" >&2
    exit 1
fi

joined=$(IFS=,; echo "${screens[*]}")
echo "capturing ${#screens[@]} screen(s) at avfoundation indices: $joined"

pids=()
timer=

# SIGINT (not SIGTERM) to ffmpeg children: AVFoundation captures ignore
# SIGTERM (it gets queued on a thread that has it blocked) but respond to
# SIGINT, which flushes the in-flight file to disk. Escalate to SIGKILL after
# a brief grace period.
kill_all() {
    [[ -n "$timer" ]] && kill "$timer" 2>/dev/null || true
    for pid in "${pids[@]}"; do
        kill -INT "$pid" 2>/dev/null || true
    done
    local deadline=$(( SECONDS + 5 ))
    while (( SECONDS < deadline )); do
        local alive=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then alive=1; break; fi
        done
        (( alive == 0 )) && break
        sleep 0.2
    done
    for pid in "${pids[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
    done
}

cleanup() {
    trap - TERM INT
    kill_all
    exit 0
}
trap cleanup TERM INT

# Rotation loop: one fragmented mp4 per screen per hour. We don't use ffmpeg's
# `-f segment` muxer because in combination with fragmented mp4 it mis-tracks
# timestamps, so segment_time never triggers a rotation. Instead, run one
# ffmpeg per screen for one wall-clock hour, then kill+restart with a fresh
# filename. Output dirs are normalized (screen-0, screen-1, ...) regardless
# of avfoundation indices.
while true; do
    day_dir="$root/$(date +%Y-%m-%d)"
    timestamp=$(date +%H-%M-%S)

    pids=()
    for i in "${!screens[@]}"; do
        out_dir="$day_dir/screen-$i"
        mkdir -p "$out_dir"
        ffmpeg -hide_banner -loglevel warning \
            -f avfoundation -framerate 5 -use_wallclock_as_timestamps 1 \
            -i "${screens[$i]}:none" \
            -c:v libx265 -preset veryfast -crf 28 \
            "$out_dir/$timestamp.mkv" &
        pids+=($!)
    done

    sleep "$segment_seconds" &
    timer=$!

    # Wake on whichever happens first: the rotation timer, or any ffmpeg
    # dying (which means restart the whole batch immediately).
    wait -n

    kill_all
    wait || true
done
