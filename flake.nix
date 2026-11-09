# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Nix flake. `nix develop` gives an FHS environment in which the official,
# checksum-pinned Godot binary (downloaded by scripts/bootstrap.sh) runs
# unmodified. The game package output is added in milestone 5.
{
  description = "Siegefall: a trebuchet physics game (development shell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs:
        let
          fhs = pkgs.buildFHSEnv {
            name = "siegefall-dev";
            targetPkgs = p: with p; [
              # tooling
              bash coreutils findutils gnused gnugrep gawk which
              curl cacert unzip xz git gnumake python3 shellcheck
              # headless tests and screenshots
              xorg.xorgserver xorg.xauth xvfb-run mesa
              # Godot runtime libraries
              xorg.libX11 xorg.libXcursor xorg.libXinerama xorg.libXrandr xorg.libXi
              xorg.libXext xorg.libXrender libxkbcommon wayland libdecor libGL
              vulkan-loader alsa-lib libpulseaudio fontconfig freetype dbus udev
              # packaging
              dpkg rpm appstream desktop-file-utils librsvg zip nsis flatpak-builder file
            ];
            runScript = "bash";
            profile = ''
              export IN_NIX_SHELL=impure
              export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            '';
          };
        in
        { default = fhs.env; });
    };
}
