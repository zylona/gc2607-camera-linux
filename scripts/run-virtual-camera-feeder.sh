#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
DEVICE="${GC2607_VCAM_DEVICE:-/dev/video${GC2607_VCAM_VIDEO_NR:-60}}"

"$ROOT/scripts/check-gc2607-hardware.sh"

SOURCE_WIDTH="${GC2607_VCAM_SOURCE_WIDTH:-1920}"
SOURCE_HEIGHT="${GC2607_VCAM_SOURCE_HEIGHT:-1080}"
OUTPUT_WIDTH="${GC2607_VCAM_WIDTH:-1280}"
OUTPUT_HEIGHT="${GC2607_VCAM_HEIGHT:-720}"
FRAMERATE="${GC2607_VCAM_FRAMERATE:-30/1}"
FORMAT="${GC2607_VCAM_FORMAT:-YUY2}"
FLIP_METHOD="${GC2607_FLIP_METHOD:-rotate-180}"

# Exposure control. The IPU6 HAL's auto-exposure hunts (brightness pumps up and
# down) as the scene changes, e.g. when a face enters the frame. Lock it to a
# fixed manual exposure by default so the picture stays steady. Override any of
# these via the environment; set GC2607_AE_MODE=auto to restore auto-exposure.
AE_MODE="${GC2607_AE_MODE:-manual}"
EXPOSURE_TIME="${GC2607_EXPOSURE_TIME:-30000}"   # microseconds (0-1000000)
GAIN="${GC2607_GAIN:-24}"                        # dB (0-100), manual AE only

AE_PROPS="ae-mode=$AE_MODE"
if [[ "$AE_MODE" == "manual" ]]; then
    AE_PROPS+=" exposure-time=$EXPOSURE_TIME gain=$GAIN"
fi

RELAYD="${GC2607_RELAYD_BIN:-/usr/bin/v4l2-relayd}"

if ! command -v "$RELAYD" >/dev/null 2>&1 && [[ ! -x "$RELAYD" ]]; then
    echo "Missing v4l2-relayd binary: $RELAYD" >&2
    echo "Install it first (e.g. paru -S v4l2-relayd)." >&2
    exit 1
fi

if [[ ! -e "$DEVICE" ]]; then
    echo "Missing virtual camera device: $DEVICE" >&2
    echo "Create it first with scripts/virtual-camera.sh prepare." >&2
    exit 1
fi

if [[ ! -w "$DEVICE" ]]; then
    echo "Virtual camera device is not writable by this user: $DEVICE" >&2
    echo "Check v4l2loopback device permissions and video-group membership." >&2
    exit 1
fi

# Prefix-specific GStreamer wiring is needed only for an in-tree HAL build.
# A packaged HAL under /usr is discovered by ld.so and GStreamer normally.
if [[ -d "$PREFIX" ]]; then
    export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
    export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
    export GST_REGISTRY="${GST_REGISTRY:-$PREFIX/gstreamer-registry.bin}"
elif [[ ! -e /usr/lib/libcamhal.so && ! -e /usr/lib/libcamhal.so.0 ]]; then
    echo "Missing packaged HAL under /usr and development HAL prefix: $PREFIX" >&2
    exit 1
fi

OUTPUT_CAPS="video/x-raw,format=${FORMAT},width=${OUTPUT_WIDTH},height=${OUTPUT_HEIGHT},framerate=${FRAMERATE}"

# Input (-i): the real GC2607 source. relayd appends its own appsink, so this
# ends at a capsfilter producing exactly the output caps. relayd runs this
# pipeline only while a consumer holds the loopback open.
#
# The final capsfilter must be spelled as an explicit element
# ("capsfilter caps=..."), not shorthand caps ("! video/x-raw,...").
# GStreamer 1.28.5 no longer parses a description that ends in shorthand
# caps (fails with: no element "video"), and relayd parses -i verbatim.
INPUT_PIPELINE="icamerasrc device-name=gc2607-uf ${AE_PROPS}"
INPUT_PIPELINE+=" ! video/x-raw,format=NV12,width=${SOURCE_WIDTH},height=${SOURCE_HEIGHT},framerate=${FRAMERATE}"
INPUT_PIPELINE+=" ! videoflip method=${FLIP_METHOD}"
INPUT_PIPELINE+=" ! videoconvert ! videoscale ! videorate"
INPUT_PIPELINE+=" ! capsfilter caps=${OUTPUT_CAPS}"

# Output (-o): relayd's producer side, held open continuously so the node stays
# discoverable even while the real camera is idle.
OUTPUT_PIPELINE="appsrc name=appsrc caps=${OUTPUT_CAPS}"
OUTPUT_PIPELINE+=" ! videoconvert ! v4l2sink name=v4l2sink device=${DEVICE} sync=false"

# Splash (-s): the cheap idle image relayd feeds to the loopback when no real
# camera is running. This is what keeps the device a valid capture node under
# exclusive_caps=1 without ever powering the GC2607 sensor.
SPLASH_PIPELINE="${GC2607_VCAM_SPLASHSRC:-videotestsrc is-live=true pattern=black ! capsfilter caps=${OUTPUT_CAPS}}"

RELAYD_ARGS=(-i "$INPUT_PIPELINE" -o "$OUTPUT_PIPELINE" -s "$SPLASH_PIPELINE")
if [[ -n "${GC2607_RELAYD_DEBUG:-}" ]]; then
    RELAYD_ARGS+=(-d)
fi

exec "$RELAYD" "${RELAYD_ARGS[@]}"
