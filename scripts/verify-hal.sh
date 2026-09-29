#!/usr/bin/env bash
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
FRAMES="${FRAMES:-120}"

if [[ -d "$PREFIX" ]]; then
    export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
    export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
    export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"
elif [[ ! -e /usr/lib/libcamhal.so && ! -e /usr/lib/libcamhal.so.0 ]]; then
    echo "Missing packaged HAL under /usr and development HAL prefix: $PREFIX" >&2
    exit 1
fi

AE_MODE="${GC2607_AE_MODE:-manual}"
EXPOSURE_TIME="${GC2607_EXPOSURE_TIME:-30000}"
GAIN="${GC2607_GAIN:-24}"
AE_PROPS=("ae-mode=$AE_MODE")
if [[ "$AE_MODE" == "manual" ]]; then
    AE_PROPS+=("exposure-time=$EXPOSURE_TIME" "gain=$GAIN")
fi

exec timeout 20s gst-launch-1.0 -e -q \
    icamerasrc device-name=gc2607-uf "${AE_PROPS[@]}" num-buffers="$FRAMES" \
    ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
    ! fakesink sync=false
