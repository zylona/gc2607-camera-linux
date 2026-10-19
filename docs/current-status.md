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
- direct HAL auto-exposure capture produces a correctly exposed image after a
  short settling period; the previous fixed manual settings were too bright
  indoors.
- Zoom previously captured video from `GC2607 Virtual Camera` with the manual
  baseline; Zoom must be rechecked with the corrected automatic-exposure path.

The packaged HAL is used from `/usr`; the PSYS dependency is managed by the
AUR `intel-ipu6-dkms-git` package. The project scripts are hardware-gated to
Huawei `VGHH-XX` systems with a `GCTI2607` sensor.

## Exposure behavior

Automatic exposure is now the default for the virtual-camera service and the
capture/verification scripts. The driver exposes the frame-timing and gain
controls required by HAL 3A. Manual exposure remains available only when
explicitly requested through `GC2607_AE_MODE=manual` and the associated
exposure/gain environment variables.

## Application acceptance

The virtual camera presents a 1280x720 YUYV stream at 30 fps. The earlier Zoom
capture proves the device path, but not the corrected automatic-exposure
quality; recheck exposure in Zoom after the updated package is installed. Allow
a short startup interval for relayd and auto-exposure to settle.

Reboot persistence was also validated: `/dev/video60` was recreated after
reboot and the enabled `gc2607-camera.service` restarted `v4l2-relayd`
automatically. A non-fatal PipeWire registration warning may appear during
early user-session startup; the V4L2 node remains usable by applications.

## 2026-10-19 MateBook deployment diagnosis

After a fresh deployment, `/dev/ipu-psys0` was present as `root:video` mode
0660, but the active desktop user was not in the `video` group and the node had
no user ACL. The camera service consequently logged `Failed to open PSYS,
error: Permission denied` and served its black fallback stream; a present
`/dev/video60` and active service did not mean real capture was working. The
packaged `uaccess` rule now grants the active seat user access without adding
the user to the broad `video` group.

The v0.1.3 reinstall also exposed a pacman transaction bug: the installer tried
to remove `icamerasrc-git` while installed GC2607 packages depended on it. The
installer now removes only the conflicting generic HAL debug package and lets
pacman replace the generic runtime HAL with the GC2607 provider atomically.
These fixes are included in v0.1.4; hardware capture must still be re-tested on
the MateBook after installation.

## 2026-10-19 exposure regression diagnosis

After the permission fix enabled real capture, the Zoom image was reported as
nearly white. The installed relayd command line showed
`ae-mode=manual exposure-time=30000 gain=24`; its HAL log also reported both
values as extreme. On the same device and lighting, a 30-frame direct HAL
capture using automatic exposure converged to mean intensity about 28,000/65,535,
while the manual 30 ms / 24 dB capture reached about 58,000/65,535. The default
virtual-camera pipeline and diagnostic scripts therefore now use `ae-mode=auto`;
manual settings remain opt-in. Zoom must be rechecked after the updated package
replaces the installed service configuration.
