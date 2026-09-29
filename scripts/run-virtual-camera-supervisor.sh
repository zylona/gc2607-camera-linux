#!/usr/bin/env bash
set -Eeuo pipefail

# v4l2-relayd normally uses V4L2_EVENT_PRI_CLIENT_USAGE to stop its input
# pipeline after the last consumer closes the loopback. Some combinations of
# v4l2loopback/relayd do not deliver that transition reliably. Keep relayd's
# splash producer alive so the virtual node remains discoverable, but restart
# it after an observed consumer closes. Restarting releases the IPU6/HAL
# buffers while preserving the virtual device.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${GC2607_VCAM_DEVICE:-/dev/video${GC2607_VCAM_VIDEO_NR:-60}}"
FEEDER="${GC2607_VCAM_FEEDER:-$ROOT/scripts/run-virtual-camera-feeder.sh}"
POLL_INTERVAL="${GC2607_VCAM_IDLE_POLL_INTERVAL:-0.5}"
IDLE_GRACE="${GC2607_VCAM_IDLE_GRACE:-2}"

child_pid=""
consumer_seen=0
idle_since=0

have_external_consumer() {
    local pid exe name

    [[ -e "$DEVICE" ]] || return 1

    for pid in $(fuser "$DEVICE" 2>/dev/null || true); do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$pid" == "$$" || "$pid" == "${child_pid:-}" ]] && continue

        exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
        name="${exe##*/}"
        [[ "$name" == "v4l2-relayd" ]] && continue
        return 0
    done

    return 1
}

start_feeder() {
    echo "Starting relayd feeder for $DEVICE."
    "$FEEDER" &
    child_pid=$!
}

stop_feeder() {
    local pid="${child_pid:-}"

    [[ -n "$pid" ]] || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    child_pid=""
}

cleanup() {
    stop_feeder
}
trap cleanup EXIT INT TERM

[[ -x "$FEEDER" ]] || {
    echo "Missing virtual-camera feeder: $FEEDER" >&2
    exit 1
}

start_feeder

while :; do
    if ! kill -0 "$child_pid" 2>/dev/null; then
        wait "$child_pid" 2>/dev/null || true
        exit 1
    fi

    if have_external_consumer; then
        consumer_seen=1
        idle_since=0
    elif (( consumer_seen )); then
        if (( idle_since == 0 )); then
            idle_since=$SECONDS
        elif (( SECONDS - idle_since >= IDLE_GRACE )); then
            echo "No external consumer on $DEVICE; restarting relayd to release the real camera."
            stop_feeder
            sleep 0.5
            start_feeder
            consumer_seen=0
            idle_since=0
        fi
    fi

    sleep "$POLL_INTERVAL"
done
