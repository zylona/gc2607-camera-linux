# GitHub installer

The repository keeps the AUR package layout for future publication, but it also
ships a standalone GitHub installer for users who do not want to clone the
source tree or run each `makepkg` command manually.

## Release usage

Download the installer and its checksum from a GitHub Release, verify it, and
run it as a normal user:

```bash
sha256sum -c gc2607-camera-installer-v0.1.0.sh.sha256
chmod +x gc2607-camera-installer-v0.1.0.sh
./gc2607-camera-installer-v0.1.0.sh
```

The installer checks the Huawei `VGHH-XX` hardware gate, installs Arch/Omarchy
dependencies, installs the public AUR dependencies (`intel-ipu6-camera-bin`,
`icamerasrc-git`, and the IPU6 DKMS package), downloads this repository, and
builds the five local packages in dependency order. It never runs as root; it
uses `sudo` only for system package/module operations.

If neither `yay` nor `paru` is installed, the installer bootstraps `yay` from
its public AUR Git repository. An AUR account is not required to install an
existing public AUR package.

The installer does not reboot automatically. Reboot after installation so the
new DKMS modules and the virtual-camera service are loaded cleanly.

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
