<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Packaging

Every package is built from the same export, with the same file layout, and
generated from the identity in [`app.env`](../app.env) and the pins in
[`toolchain.lock`](../toolchain.lock). To rename the game or bump its version,
edit `app.env` and rebuild; no packaging file spells the name out by hand.

```bash
make dev                         # once: Godot, export templates, godot-rapier
make build ARGS="--target all"   # build/export/{linux-x86_64,linux-arm64,windows-x86_64}
make package                     # dist/: every format whose tool is installed
make test-install                # install.sh/uninstall.sh in a throw-away HOME
make test-containers             # install + run each package in distro containers
```

`scripts/build.sh --help` and `scripts/package.sh --help` list every option.
`make package ARGS="deb rpm"` builds only those formats; a format whose tool
is missing is skipped with a note (or is an error when asked for by name).

## What a build contains

`scripts/build.sh` runs the pinned Godot headlessly with the pinned export
templates (passed as absolute `custom_template` paths, so it never depends on
the editor's own template folder) and writes, per target:

| File | |
|---|---|
| `siegefall` / `Siegefall.exe` | Godot export template with the game data (`.pck`) appended |
| `libgodot_rapier.*.so` / `.dll` | the physics engine (GDExtension), loaded from next to the executable |
| `THIRD-PARTY-NOTICES.txt` | Godot's licence and every notice compiled into it, plus godot-rapier's |
| `BUILD_INFO` | version, target, Godot release, commit |

**Never strip the executable.** The game data is appended to it, and `strip`,
`objcopy` or debug-info splitting cut it off. Every package here disables
stripping (`options=('!strip')`, `%global __strip /bin/true`,
`strip: false`, `dontStrip`). The Nix package goes one step further and keeps
the `.pck` as a separate file (`--no-embed-pck`), because patchelf rewrites
the executable.

Godot only links glibc (2.28 or newer); X11, Wayland, OpenGL, Vulkan, ALSA,
PulseAudio, fontconfig, D-Bus and udev are opened at run time, so each package
declares them by hand.

## Installed layout

Same in every Linux package, under `/usr` (packages), `/usr/local`
(`install.sh --system`) or `~/.local` (`install.sh`):

```
bin/siegefall -> ../lib/siegefall/siegefall
lib/siegefall/{siegefall, libgodot_rapier.*.so}
share/applications/io.github.oreo1298.Siegefall.desktop
share/metainfo/io.github.oreo1298.Siegefall.metainfo.xml
share/icons/hicolor/{16..512}/apps/io.github.oreo1298.Siegefall.png (+ scalable SVG)
share/man/man6/siegefall.6.gz
share/doc/siegefall/   share/licenses/siegefall/
```

Player data never lives there: saves and castles go to
`$XDG_DATA_HOME/siegefall`, settings to `$XDG_CONFIG_HOME/siegefall`.

## Formats

| Format | Made by | Notes |
|---|---|---|
| tarball | `tar` | `files/` tree plus `install.sh`/`uninstall.sh`; runnable in place via the `siegefall` link |
| AppImage | `mksquashfs` + the pinned [type2 runtime](https://github.com/AppImage/type2-runtime) | no appimagetool; runtime SHA-256 in `toolchain.lock` |
| deb | `dpkg-deb` | `/usr/games` link for Debian; DEP-5 copyright; lintian-clean with overrides for Godot's static libraries |
| rpm | `rpmbuild` | binary RPM from the staged tree; one host builds x86_64 and aarch64; soname dependencies work on Fedora and openSUSE |
| Flatpak | `flatpak-builder` | Freedesktop runtime 25.08; Wayland with X11 fallback, PulseAudio, DRI, gamepads; **no network permission**. `dist/` gets a manifest with release URLs (for Flathub), `build/pkg/flatpak/` one with local paths |
| AUR | templates | `siegefall-bin` (release tarballs) and `siegefall` (from source with the pinned Godot; downloads the 1.3 GB template archive but unpacks one file) |
| Nix | `flake.nix` | from source in the sandbox with the pinned Godot (`autoPatchelf`), runtime libraries added to the RUNPATH |
| Windows zip | `zip` | portable folder |
| Windows installer | `makensis` | per-user (no admin), Start menu + optional desktop shortcut, listed in Apps & features; the uninstaller only deletes saves if the box is ticked |

## Install scripts

`scripts/install.sh` copies a staged tree into the prefix and writes
`lib/siegefall/.install-manifest`. Re-running it removes the previous install
first, so upgrades leave nothing stale. It also places `uninstall.sh` (and the
identity it needs) next to the game, so removal works after the repository or
tarball is gone. Packagers use `install.sh --prefix /usr --destdir "$pkgdir"`,
which skips the manifest and the menu cache refresh.

`uninstall.sh` removes only files in the manifest (refusing absolute or `..`
entries), then the game's own empty folders. `--purge` also deletes saves,
castles and settings, after asking (or with `--yes`).

## Testing

* `make test-install`: install, re-install, launch, uninstall (saves kept),
  `--purge`, and the same from the tarball after deleting it.
* `make test-containers`: Arch (makepkg the `-bin` PKGBUILD from the local
  tarball, then `pacman -U`), Ubuntu and Debian (apt), Fedora (dnf),
  Tumbleweed (zypper) and Void (tarball as a normal user). Each runs the
  headless smoke test, checks the menu entry, icon and metadata, uninstalls,
  and checks nothing is left. Behind a TLS-intercepting proxy, pass a CA
  bundle with `--engine-arg -v --engine-arg ca.pem:/path/in/image:ro` and
  switch mirrors with `--setup`.
* CI (`.github/workflows/packages.yml`) builds everything, validates the
  desktop file, AppStream data and the deb, runs the AppImage, then installs
  and starts every package on its own system: the six distributions above,
  Linux arm64 (AppImage, deb, rpm, tarball), the Flatpak bundle, the Nix
  package, and the Windows zip and installer (silent install, start,
  uninstall).

## Releasing

Nothing in this repository publishes anything. For a release:

1. Bump `APP_VERSION` in `app.env`, add a `CHANGELOG.md` entry, `make sync-identity`.
2. Tag `v<version>` and push it. CI keeps the packages as the `dist`
   artifact of that run.
3. Attach the files to a GitHub release by hand.
4. AUR: `make package ARGS=aur` writes both PKGBUILDs with the release
   tarballs' SHA-256 (the files in `dist/` must be the ones uploaded). On Arch,
   `makepkg --printsrcinfo > .SRCINFO`, then push to the AUR.
5. Flathub: submit `dist/io.github.oreo1298.Siegefall.yml` (it downloads the
   release tarballs).
