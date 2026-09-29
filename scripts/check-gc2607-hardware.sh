#!/usr/bin/env bash
set -euo pipefail

vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"

if [[ "${vendor,,}" != *huawei* || "${product^^}" != "VGHH-XX" ]]; then
    echo "GC2607 camera integration is disabled on ${vendor:-unknown} ${product:-unknown}." >&2
    exit 1
fi

if [[ ! -e /sys/bus/acpi/devices/GCTI2607:00 ]] &&
   ! find /sys/bus/i2c/devices -maxdepth 1 -name '*-0037' -print -quit 2>/dev/null | grep -q .; then
    echo "Huawei VGHH-XX detected, but the GCTI2607 sensor is absent." >&2
    exit 1
fi

exit 0
