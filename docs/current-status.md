# Current Camera Status

## Basic implementation

The Huawei MateBook X Pro 2024 camera is operational on the current Omarchy
kernel through the following stack:

```text
GC2607 V4L2 driver -> IPU6 bridge/ISYS -> Intel libcamhal + PSYS
                    -> icamerasrc -> GStreamer
```

Validated locally:

- `GCTI2607:00` is detected and connected to IPU6;
- `gc2607`, the patched `ipu-bridge`, and IPU6 PSYS load through DKMS;
- `icamerasrc device-name=gc2607-uf` negotiates NV12 1920x1080 at 30 fps;
- JPEG frames are produced successfully;
- manual exposure mode produces a usable image.
- Zoom has successfully captured video from `GC2607 Virtual Camera`.

The packaged HAL is used from `/usr`; the PSYS dependency is managed by the
AUR `intel-ipu6-dkms-git` package. The project scripts are hardware-gated to
Huawei `VGHH-XX` systems with a `GCTI2607` sensor.

## Deferred work

Automatic exposure is intentionally not part of the current acceptance gate.
The Intel HAL AIQ path declares automatic exposure support, but this hardware
currently reports unsupported control writes and a missing runtime AIQD file.
The stable baseline therefore uses manual exposure defaults in the capture and
virtual-camera pipelines:

- exposure time: 30000 microseconds;
- analogue gain: 24 dB.

Future work: identify the failing HAL-to-V4L2 control mappings, resolve the
AIQD/3A configuration, and validate automatic exposure across changing light.

## Application acceptance

The basic implementation is accepted for video conferencing after successful
testing in Zoom. The virtual camera presents a 1280x720 YUYV stream at 30 fps;
the first frames may remain on the relayd splash or be underexposed while the
manual exposure pipeline starts, so applications should be given a short
startup interval before judging the image.

Reboot persistence was also validated: `/dev/video60` was recreated after
reboot and the enabled `gc2607-camera.service` restarted `v4l2-relayd`
automatically. A non-fatal PipeWire registration warning may appear during
early user-session startup; the V4L2 node remains usable by applications.
