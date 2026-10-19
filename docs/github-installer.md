# GitHub installer

The repository keeps the AUR package layout for future publication, but it also
ships a standalone GitHub installer for users who do not want to clone the
source tree or run each `makepkg` command manually.

## Release usage

Download the installer and its checksum from a GitHub Release, verify it, and
run it as a normal user:

```bash
sha256sum -c gc2607-camera-installer-v0.1.4.sh.sha256
chmod +x gc2607-camera-installer-v0.1.4.sh
./gc2607-camera-installer-v0.1.4.sh
```

The installer checks the Huawei `VGHH-XX` hardware gate and installs the
Arch/Omarchy dependencies and Intel IPU6 userspace/runtime packages. It then
builds and installs the GC2607 DKMS modules and GC2607-specific HAL before
installing `icamerasrc-git`, whose `ipu6-camera-hal` dependency is satisfied by
the GC2607 provider. If the generic HAL and `icamerasrc-git` are already
installed, pacman replaces the generic runtime provider in the same transaction
that installs the GC2607-specific provider. The generic HAL debug package is
removed first to avoid debug-file ownership conflicts. `icamerasrc-git` remains
installed throughout, so installed GC2607 meta-packages never lose a required
dependency during the transition.
Local packages are built
without `makepkg -i`; the installer invokes `sudo pacman` from its main shell
so sudo authentication is reused across the long build and any needed prompt
remains attached to the visible terminal. It never runs as root.

If neither `yay` nor `paru` is installed, the installer bootstraps `yay` from
its public AUR Git repository. An AUR account is not required to install an
existing public AUR package.

The installer does not reboot automatically. Reboot after installation so the
new DKMS modules and the virtual-camera service are loaded cleanly.

The package also installs a udev `uaccess` rule for `/dev/ipu-psys0`. This gives
the active local desktop session access to IPU6 image processing without
requiring the user to join the broad `video` group. The installer reloads the
rule and retriggers the PSYS device so the permission takes effect immediately.

## Testing the current branch directly

For development, the same script can be run from a checkout:

```bash
./install-gc2607-camera.sh --ref main
```

The `--skip-hardware-check` option is only for packaging tests and should not
be used on a normal installation.

## Release creation

Pushing a tag matching `v*` activates `.github/workflows/release-installer.yml`.
The workflow creates a version-pinned installer and a SHA-256 checksum as
GitHub Release assets. The installer still compiles DKMS modules on the target
machine; the release asset is an installer program, not a portable kernel
binary.
