# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Nix flake.
#   nix build            the game (packaging/nix/package.nix), from source
#   nix run              play it
#   nix develop          an FHS environment in which the official,
#                        checksum-pinned Godot (scripts/bootstrap.sh) runs
{
  description = "Siegefall: a trebuchet physics game";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # app.env and toolchain.lock hold KEY="value" lines; read them so the
      # game's identity and pins stay in one place.
      readEnv =
        file:
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile file);
          pairs = builtins.filter (m: m != null) (map (builtins.match ''([A-Z0-9_]+)="([^"]*)"'') lines);
        in
        builtins.listToAttrs (
          map (m: {
            name = builtins.elemAt m 0;
            value = builtins.elemAt m 1;
          }) pairs
        );
      app = readEnv ./app.env;
      lock = readEnv ./toolchain.lock;
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          game = pkgs.callPackage ./packaging/nix/package.nix {
            inherit app lock;
            src = self;
            srcDate = self.lastModified or 0;
          };
        in
        {
          ${app.APP_SLUG} = game;
          default = game;
        }
      );

      devShells = forAllSystems (
        pkgs:
        let
          fhs = pkgs.buildFHSEnv {
            name = "${app.APP_SLUG}-dev";
            targetPkgs =
              p: with p; [
                # tooling
                bash
                coreutils
                findutils
                gnused
                gnugrep
                gawk
                which
                curl
                cacert
                unzip
                xz
                git
                gnumake
                python3
                shellcheck
                # headless tests and screenshots
                xorg.xorgserver
                xorg.xauth
                xvfb-run
                mesa
                # Godot runtime libraries
                xorg.libX11
                xorg.libXcursor
                xorg.libXinerama
                xorg.libXrandr
                xorg.libXi
                xorg.libXext
                xorg.libXrender
                libxkbcommon
                wayland
                libdecor
                libGL
                vulkan-loader
                alsa-lib
                libpulseaudio
                fontconfig
                freetype
                dbus
                udev
                # packaging
                dpkg
                rpm
                squashfsTools
                appstream
                desktop-file-utils
                zip
                nsis
                flatpak-builder
                file
              ];
            runScript = "bash";
            profile = ''
              export IN_NIX_SHELL=impure
              export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            '';
          };
        in
        {
          default = fhs.env;
        }
      );
    };
}
