# GC2607 project adaptations

This repository does not replace the Windows camera implementation wholesale.
It combines the upstream Linux GC2607 sensor work with a small set of board-,
IPU6-, and HAL-specific adaptations validated on the Huawei MateBook X Pro
2024 (`VGHH-XX`).

## Kernel sensor driver

The sensor driver adapts the reference GC2607 register sequence to the laptop's
19.2 MHz clock and keeps a clean 30 fps mode:

- uses the laptop's `GCTI2607` ACPI/I2C identity;
- sets the 1920x1080 SGRBG10 mode and two-lane CSI-2 timing;
- uses the shipped 30 fps timing (`HTS=1959`, `VTS=1116`) while keeping the
  known-good 672 Mbps IPU6 link configuration;
- exposes standard `hblank`, `vblank`, `pixel_rate`, exposure, flip, and gain
  controls required by the V4L2/IPU6 stack;
- maps analogue gain to the AIQ's 1/64 code units and accepts the HAL's fixed
  digital-gain write instead of returning `EINVAL`.

The timing and control changes are functional compatibility work. They do not
try to make the image brighter or darker directly. The gain-unit correction
actually prevents the HAL from pinning the sensor at maximum analogue gain.
Details and measurements are in `gc2607-kernel/FINDINGS.md`.

## IPU6 bridge

The patched `ipu-bridge` adds the `GCTI2607` sensor table entry and the
MateBook's upside-down sensor-mount DMI handling. Without this graph entry,
the sensor can probe successfully but IPU6 does not connect the camera.

## IPU6 HAL

The HAL patches make GC2607 a recognized camera profile and add the missing
sensor XML. They also pad the 1920x1080 RAW10 input to the 1928x1088 dimensions
expected by this IPU6 PSYS graph before processing, then restore the original
buffer bookkeeping afterward. A compiler compatibility patch relaxes an old
`-Werror` setting for current toolchains.

The project also ships the GC2607 AIQB, graph settings, and sensor tuning
assets extracted during bring-up. These are the parts that influence ISP/3A
image rendering most directly.

## Current exposure behavior

The virtual-camera pipeline currently chooses manual exposure defaults:

```text
exposure-time=30000 microseconds
gain=24 dB
```

This is a runtime policy in `scripts/run-virtual-camera-feeder.sh`, not a
replacement for the sensor's factory tuning. It was chosen because the HAL's
automatic-exposure path still hunts or emits unsupported control writes on this
hardware. Consequently, a scene can look too bright or too dark when the
lighting changes. The setting can be overridden for experiments:

```bash
systemctl --user set-environment GC2607_EXPOSURE_TIME=22000 GC2607_GAIN=10
systemctl --user restart gc2607-camera.service
```

Automatic exposure remains deferred work. The likely work is in AIQ/AIQD and
HAL-to-V4L2 control mapping, not merely changing one brightness threshold.
