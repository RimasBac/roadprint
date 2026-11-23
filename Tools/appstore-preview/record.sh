#!/usr/bin/env bash
# Record the booted simulator's screen while the preview UI test runs.
#   record.sh start DIR   writes DIR/raw.mov, DIR/record.pid and DIR/record-start.txt (unix seconds)
#   record.sh stop DIR    ends the recording and waits until raw.mov is complete
set -euo pipefail
action=${1:?start or stop}
dir=${2:?output directory}
mkdir -p "$dir"
case "$action" in
  start)
    xcrun simctl io "${SIM_UDID:?}" recordVideo --codec=h264 --force "$dir/raw.mov" 2>"$dir/record.log" &
    echo $! > "$dir/record.pid"
    for _ in $(seq 1 100); do
      if grep -q 'Recording started' "$dir/record.log"; then
        # The UI test's marks use the same clock, so scenes can be found in the recording.
        python3 -c 'import time; print(f"{time.time():.3f}")' > "$dir/record-start.txt"
        exit 0
      fi
      kill -0 "$(cat "$dir/record.pid")" 2>/dev/null || break
      sleep 0.1
    done
    cat "$dir/record.log" >&2
    echo 'Simulator recording did not start' >&2
    exit 1;;
  stop)
    pid=$(cat "$dir/record.pid")
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 300); do kill -0 "$pid" 2>/dev/null || exit 0; sleep 0.1; done
    echo 'Simulator recording did not finish' >&2
    exit 1;;
  *) echo 'Usage: record.sh start|stop DIR' >&2; exit 2;;
esac
