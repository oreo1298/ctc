# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Builds the game from source with the exact Godot release it is pinned to
# (official binaries and export templates, checked against toolchain.lock),
# using the same scripts as every other package.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  python3,
  autoPatchelfHook,
  libGL,
  vulkan-loader,
  xorg,
  libxkbcommon,
  wayland,
  libdecor,
  alsa-lib,
  libpulseaudio,
  fontconfig,
  dbus,
  udev,
  # From flake.nix: app.env and toolchain.lock as attribute sets, the
  # source tree and its commit time.
  app,
  lock,
  src,
  srcDate ? 0,
}:
let
  garch =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "arm64";
    }
    .${stdenv.hostPlatform.system} or (throw "unsupported system ${stdenv.hostPlatform.system}");
  tag = "${lock.GODOT_VERSION}-${lock.GODOT_STATUS}";
  godotZip = fetchurl {
    url = "${lock.GODOT_RELEASE_URL}/Godot_v${tag}_linux.${garch}.zip";
    sha512 = if garch == "x86_64" then lock.GODOT_SHA512_LINUX_X86_64 else lock.GODOT_SHA512_LINUX_ARM64;
  };
  templates = fetchurl {
    url = "${lock.GODOT_RELEASE_URL}/Godot_v${tag}_export_templates.tpz";
    sha512 = lock.GODOT_SHA512_TEMPLATES;
  };
  rapier = fetchurl {
    url = lock.RAPIER_URL;
    sha256 = lock.RAPIER_SHA256;
  };
in
stdenv.mkDerivation {
  pname = app.APP_SLUG;
  version = app.APP_VERSION;
  inherit src;

  nativeBuildInputs = [
    unzip
    python3
    autoPatchelfHook
  ];

  # Godot opens these with dlopen() at run time; autoPatchelfHook adds them
  # to the game's RUNPATH.
  runtimeDependencies = [
    libGL
    vulkan-loader
    xorg.libX11
    xorg.libXcursor
    xorg.libXext
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXi
    xorg.libXrender
    libxkbcommon
    wayland
    libdecor
    alsa-lib
    libpulseaudio
    fontconfig
    dbus
    udev
  ];

  # The metainfo release date comes from the commit, not from 1980.
  SOURCE_DATE_EPOCH = toString (if srcDate > 0 then srcDate else 315532800);

  dontConfigure = true;
  # Godot binaries must not be stripped.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home XDG_DATA_HOME=$TMPDIR/home/data
    export XDG_CONFIG_HOME=$TMPDIR/home/config XDG_CACHE_HOME=$TMPDIR/home/cache
    mkdir -p $HOME $TMPDIR/godot $TMPDIR/templates
    unzip -q ${godotZip} -d $TMPDIR/godot
    godot=$TMPDIR/godot/Godot_v${tag}_linux.${garch}
    chmod +x $godot
    autoPatchelf $TMPDIR/godot
    unzip -q -j ${templates} templates/linux_release.${garch} -d $TMPDIR/templates
    patchShebangs scripts tools
    bash -ec 'source scripts/lib/common.sh; load_identity; install_rapier_addon game/addons "$1"' _ ${rapier}
    # A separate .pck: patching the ELF must not move data appended to it.
    ./scripts/build.sh --target linux-${garch} --no-embed-pck --godot $godot --templates $TMPDIR/templates
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    ./scripts/install.sh --prefix $out --destdir / --arch ${garch}
    rm -f $out/lib/${app.APP_SLUG}/BUILD_INFO
    runHook postInstall
  '';

  meta = {
    description = app.APP_SUMMARY;
    homepage = app.APP_HOMEPAGE;
    license = with lib.licenses; [
      mit
      cc-by-sa-40
      ofl
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode # Godot export templates
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = app.APP_SLUG;
  };
}
