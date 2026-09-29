# AUR publishing plan

This repository is the maintained source project for the Huawei MateBook X Pro
2024 GC2607 camera stack. The AUR repositories should contain only packaging
metadata and helper files; they should fetch this repository as their source.

## Package layout

Publish these package bases in this order:

1. `gc2607-dkms-git`
2. `gc2607-ipu-bridge-dkms-git`
3. `gc2607-ipu6-camera-hal-git`
4. `gc2607-virtual-camera-git`
5. `gc2607-camera-git`

The fifth package is the user-facing meta package. Once a tagged, fixed source
release exists, the package names can be changed from `-git` to stable names and
the install command can become `yay -S gc2607-camera`.

## Before publishing

- The source repository is `https://github.com/zylona/gc2607-camera-linux`.
- Commit the validated local changes. A release tag is optional for the current
  `-git` packages; it becomes useful later if we publish fixed, non-VCS package
  names.
- Remove build output such as `src/`, `pkg/`, and `*.pkg.tar.zst` from the Git
  repository.
- The maintainer has confirmed that the `assets/hal/*.aiqb` and related tuning
  files may be redistributed publicly. These came from a Windows driver payload
  and the confirmation should remain documented in `CREDITS.md`.
- Verify every package in a clean Arch build environment.

## Local package checks

From each package directory:

```bash
makepkg -Cfs
makepkg --printsrcinfo > .SRCINFO
```

Do not upload the generated binary package to the AUR. Upload `PKGBUILD`,
`.SRCINFO`, `LICENSE`, and any required `.install` or patch files.

## AUR account setup

As of 2026-09-29, new AUR account registration is temporarily paused by the
AUR administrators. Do not automate retries; wait for registration to reopen.

Create an AUR account and add a dedicated SSH public key. The local SSH config
can use:

```sshconfig
Host aur.archlinux.org
    User aur
    IdentityFile ~/.ssh/aur
```

Generate the metadata and push each package base to its own AUR Git repository:

```bash
git clone ssh://aur@aur.archlinux.org/gc2607-camera-git.git
cd gc2607-camera-git
cp /path/to/PKGBUILD /path/to/.SRCINFO .
git add PKGBUILD .SRCINFO LICENSE
git commit -m "Initial AUR package"
git push origin master
```

Repeat for the four component packages before pushing the meta package. Then
the complete stack can be restored with:

```bash
yay -S gc2607-camera-git
```
