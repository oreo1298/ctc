#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Set up a development machine: system packages, the pinned Godot editor and
# export templates (checksum-verified, user-level, no root), a Python venv
# with the linters, and the GUT test framework. Safe to re-run.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

usage() {
	cat <<EOF
Usage: scripts/bootstrap.sh [options]

Prepares this machine for ${APP_NAME} development. Re-running is safe: work
that is already done (and verified) is skipped.

Steps:
  1. Detect the distro (/etc/os-release ID and ID_LIKE) and install the
     development + packaging dependencies with its package manager (sudo).
  2. Download the pinned Godot ${GODOT_TAG} editor into
     $(sf_cache_dir)/godot/ and verify its SHA-512.
  3. Download + verify the export templates and install them into
     $(godot_templates_dir)
  4. Create .venv/ with pinned gdtoolkit, reuse, jsonschema, shellcheck.
  5. Fetch the pinned GUT test framework into game/addons/gut and the
     pinned godot-rapier 2D physics extension into game/addons/godot-rapier2d.
Steps 2-5 never need root.

Options:
  -n, --dry-run        Print what would be done; change nothing.
  -y, --yes            Do not ask the package manager for confirmation.
      --refresh        Refresh the package database before installing.
      --skip-packages  Skip step 1 (no sudo needed at all).
      --packages-only  Only do step 1.
      --editor-only    Skip the ~1.3 GB export templates (step 3).
      --no-venv        Skip step 4.
      --no-gut         Skip step 5.
      --print-deps     Print the package list for this distro and exit.
      --os-release F   Read distro info from F instead of /etc/os-release
                       (for testing the detection logic).
  -h, --help           Show this help.

Supported package managers: pacman (Arch, CachyOS, Manjaro, EndeavourOS),
apt (Debian, Ubuntu, Mint, Pop!_OS), dnf (Fedora, Nobara), zypper
(openSUSE Leap/Tumbleweed), xbps (Void), emerge (Gentoo), and NixOS via
'nix develop'. Image-based systems (Silverblue, Kinoite, Bazzite, SteamOS)
are pointed at distrobox/Flatpak instead of layering packages.
EOF
}

YES=0 REFRESH=0 SKIP_PKGS=0 PKGS_ONLY=0 EDITOR_ONLY=0 NO_VENV=0 NO_GUT=0 PRINT_DEPS=0
OS_RELEASE_FILE="/etc/os-release"
OS_RELEASE_OVERRIDDEN=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --dry-run) DRY_RUN=1 ;;
	-y | --yes) YES=1 ;;
	--refresh) REFRESH=1 ;;
	--skip-packages) SKIP_PKGS=1 ;;
	--packages-only) PKGS_ONLY=1 ;;
	--editor-only) EDITOR_ONLY=1 ;;
	--no-venv) NO_VENV=1 ;;
	--no-gut) NO_GUT=1 ;;
	--print-deps) PRINT_DEPS=1 ;;
	--os-release)
		[[ $# -ge 2 ]] || die "--os-release needs a file argument"
		OS_RELEASE_FILE="$2" OS_RELEASE_OVERRIDDEN=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done
export DRY_RUN

# ------------------------------------------------------ distro detection ---
OS_ID='' OS_ID_LIKE='' OS_VARIANT_ID='' OS_PRETTY=''
read_os_release() {
	[[ -r "${OS_RELEASE_FILE}" ]] || return 1
	# Parse in a subshell so the file cannot clobber our variables.
	local parsed
	parsed="$(
		# shellcheck disable=SC1090
		. "${OS_RELEASE_FILE}"
		printf '%s\n%s\n%s\n%s\n' "${ID:-}" "${ID_LIKE:-}" "${VARIANT_ID:-}" "${PRETTY_NAME:-${NAME:-unknown}}"
	)"
	{
		IFS= read -r OS_ID
		IFS= read -r OS_ID_LIKE
		IFS= read -r OS_VARIANT_ID
		IFS= read -r OS_PRETTY
	} <<<"${parsed}"
}

is_immutable() {
	case "${OS_ID}" in
	steamos | bazzite | aurora | bluefin | fedora-coreos | endless | vanilla) return 0 ;;
	esac
	case "${OS_VARIANT_ID}" in
	silverblue | kinoite | sericea | onyx | cosmic-atomic | atomic | *-atomic | bazzite* | steamdeck) return 0 ;;
	esac
	# Only trust live-system markers when we are looking at the live system.
	if [[ "${OS_RELEASE_OVERRIDDEN}" == 0 && -e /run/ostree-booted ]]; then
		return 0
	fi
	return 1
}

# Echo the package-manager family for an ID, or nothing.
family_for_id() {
	case "$1" in
	arch | cachyos | manjaro | manjaro-arm | endeavouros | garuda | artix | archarm) echo pacman ;;
	debian | ubuntu | linuxmint | pop | elementary | zorin | neon | raspbian | kali | devuan) echo apt ;;
	fedora | nobara | rhel | centos | rocky | almalinux | ultramarine) echo dnf ;;
	opensuse-leap | opensuse-tumbleweed | opensuse-slowroll | opensuse | suse | sles) echo zypper ;;
	void) echo xbps ;;
	gentoo | funtoo) echo emerge ;;
	nixos) echo nix ;;
	esac
}

detect_family() {
	local f tok
	f="$(family_for_id "${OS_ID}")"
	if [[ -z "${f}" ]]; then
		for tok in ${OS_ID_LIKE}; do
			f="$(family_for_id "${tok}")"
			[[ -n "${f}" ]] && break
		done
	fi
	printf '%s' "${f}"
}

# -------------------------------------------------------- package lists ---
# REQUIRED: needed to run the editor/tests/screenshot harness headlessly.
# OPTIONAL: linting and packaging extras; installed one by one, failures are
# reported but do not stop the bootstrap.
pkgs_required() {
	case "$1" in
	pacman) echo curl ca-certificates unzip xz git make python xorg-server-xvfb xorg-xauth mesa fontconfig \
		libx11 libxcursor libxinerama libxrandr libxi libxext libxrender libxkbcommon libglvnd ;;
	apt) echo curl ca-certificates unzip xz-utils git make python3 python3-venv xvfb xauth \
		libgl1-mesa-dri libgl1 libegl1 fontconfig libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 \
		libxext6 libxrender1 libxkbcommon0 ;;
	dnf) echo curl ca-certificates unzip xz git make python3 xorg-x11-server-Xvfb xorg-x11-xauth \
		mesa-dri-drivers mesa-libGL mesa-libEGL fontconfig libX11 libXcursor libXinerama libXrandr libXi \
		libXext libXrender libxkbcommon ;;
	zypper) echo curl ca-certificates unzip xz git make python3 xorg-x11-server-Xvfb xauth Mesa-dri \
		Mesa-libGL1 Mesa-libEGL1 fontconfig libX11-6 libXcursor1 libXinerama1 libXrandr2 libXi6 libXext6 \
		libXrender1 libxkbcommon0 ;;
	xbps) echo curl ca-certificates unzip xz git make python3 python3-pip xorg-server-xvfb xauth mesa-dri \
		fontconfig libX11 libXcursor libXinerama libXrandr libXi libXext libXrender libxkbcommon libglvnd ;;
	emerge) echo net-misc/curl app-misc/ca-certificates app-arch/unzip app-arch/xz-utils dev-vcs/git \
		dev-build/make dev-lang/python x11-base/xorg-server x11-apps/xauth media-libs/mesa \
		media-libs/fontconfig x11-libs/libX11 x11-libs/libXcursor x11-libs/libXinerama x11-libs/libXrandr \
		x11-libs/libXi x11-libs/libXext x11-libs/libXrender x11-libs/libxkbcommon ;;
	esac
}

pkgs_optional() {
	case "$1" in
	pacman) echo shellcheck dpkg rpm-tools appstream desktop-file-utils librsvg zip nsis flatpak-builder file \
		wayland libdecor alsa-lib libpulse ;;
	apt) echo shellcheck dpkg-dev rpm appstream desktop-file-utils librsvg2-bin zip nsis flatpak-builder file \
		libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0 libasound2 libpulse0 ;;
	dnf) echo ShellCheck dpkg rpm-build appstream desktop-file-utils librsvg2-tools zip mingw32-nsis \
		flatpak-builder file libwayland-client libwayland-cursor libwayland-egl libdecor alsa-lib pulseaudio-libs ;;
	zypper) echo ShellCheck dpkg rpm-build AppStream desktop-file-utils rsvg-convert zip mingw32-cross-nsis \
		flatpak-builder file libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0 alsa libpulse0 ;;
	xbps) echo shellcheck dpkg rpm AppStream desktop-file-utils librsvg-utils zip nsis flatpak-builder file \
		wayland libdecor alsa-lib libpulseaudio ;;
	emerge) echo dev-util/shellcheck-bin app-arch/dpkg app-arch/rpm dev-libs/appstream \
		dev-util/desktop-file-utils gnome-base/librsvg app-arch/zip dev-util/nsis dev-util/flatpak-builder \
		sys-apps/file dev-libs/wayland gui-libs/libdecor media-libs/alsa-lib media-libs/libpulse ;;
	esac
}

print_generic_deps() {
	cat <<'EOF'
Needed on any distro (names vary):
  required : curl, CA certificates, unzip, xz, git, make, Python 3 (with venv),
             Xvfb + xauth (headless tests/screenshots), Mesa (software GL/EGL),
             fontconfig, libX11, libXcursor, libXinerama, libXrandr, libXi,
             libXext, libXrender, libxkbcommon
  optional : shellcheck, dpkg-deb, rpmbuild, appstreamcli, desktop-file-validate,
             rsvg-convert, zip, makensis (NSIS), flatpak-builder, file,
             Wayland client libs + libdecor, ALSA, PulseAudio/PipeWire-pulse
EOF
}

# --------------------------------------------------------- installation ---
SUDO=()
pick_sudo() {
	if [[ "${EUID}" -eq 0 ]]; then
		SUDO=()
	elif have_cmd sudo; then
		SUDO=(sudo)
	elif have_cmd doas; then
		SUDO=(doas)
	else
		return 1
	fi
}

# install_cmd FAMILY -> sets INSTALL=(...) and REFRESH_CMD=(...)
INSTALL=() REFRESH_CMD=()
set_install_cmd() {
	case "$1" in
	pacman)
		REFRESH_CMD=(pacman -Sy)
		INSTALL=(pacman -S --needed)
		[[ "${YES}" == 1 ]] && INSTALL+=(--noconfirm)
		;;
	apt)
		REFRESH_CMD=(apt-get update)
		INSTALL=(apt-get install --no-install-recommends)
		[[ "${YES}" == 1 ]] && INSTALL+=(-y)
		;;
	dnf)
		REFRESH_CMD=(dnf makecache)
		INSTALL=(dnf install --setopt=install_weak_deps=False)
		[[ "${YES}" == 1 ]] && INSTALL+=(-y)
		;;
	zypper)
		REFRESH_CMD=(zypper --non-interactive refresh)
		INSTALL=(zypper)
		[[ "${YES}" == 1 ]] && INSTALL+=(--non-interactive)
		INSTALL+=(install --no-recommends)
		;;
	xbps)
		REFRESH_CMD=(xbps-install -S)
		INSTALL=(xbps-install)
		[[ "${YES}" == 1 ]] && INSTALL+=(-y)
		;;
	emerge)
		REFRESH_CMD=(emerge --sync)
		INSTALL=(emerge --noreplace --oneshot)
		if [[ "${YES}" == 1 ]]; then INSTALL+=(--ask=n); else INSTALL+=(--ask); fi
		;;
	esac
}

install_packages() {
	local family="$1"
	local -a req opt
	read -r -a req <<<"$(pkgs_required "${family}")"
	read -r -a opt <<<"$(pkgs_optional "${family}")"
	set_install_cmd "${family}"

	if ! pick_sudo; then
		warn "not root and neither sudo nor doas is available; cannot install system packages."
		warn "Ask an administrator to run:"
		warn "  ${INSTALL[*]} ${req[*]}"
		warn "Continuing with the user-level steps."
		return 0
	fi

	if [[ "${REFRESH}" == 1 ]]; then
		log "Refreshing the ${family} package database"
		run "${SUDO[@]}" "${REFRESH_CMD[@]}"
	fi
	if [[ "${family}" == emerge ]]; then
		warn "Gentoo: Xvfb needs x11-base/xorg-server built with USE=xvfb."
	fi
	log "Installing required packages (${family}): ${req[*]}"
	run "${SUDO[@]}" "${INSTALL[@]}" "${req[@]}" ||
		die "installing required packages failed. Fix the error above and re-run (or use --skip-packages)."

	log "Installing optional packages one by one (failures are not fatal)"
	local p missing=()
	for p in "${opt[@]}"; do
		if [[ "${DRY_RUN}" == 1 ]]; then
			run "${SUDO[@]}" "${INSTALL[@]}" "${p}"
		elif ! "${SUDO[@]}" "${INSTALL[@]}" "${p}" >/dev/null 2>&1; then
			missing+=("${p}")
		fi
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		warn "optional packages not installed: ${missing[*]}"
		warn "linting falls back to the pinned tools in .venv; packaging targets that need them will say so."
	fi
	ok "system packages"
}

immutable_advice() {
	cat >&2 <<EOF

${OS_PRETTY} is an image-based (immutable) system, so bootstrap.sh will not
layer packages onto it. Pick one of these instead:

  * distrobox (recommended for development; the container shares your home,
    display and GPU):
        distrobox create --name ${APP_SLUG}-dev --image docker.io/library/archlinux:latest
        distrobox enter ${APP_SLUG}-dev -- ./scripts/bootstrap.sh --yes --refresh
        distrobox enter ${APP_SLUG}-dev -- make run

  * Flatpak, to play or edit without a dev toolchain:
        flatpak install flathub org.godotengine.Godot
    (its Godot version may differ from the pinned ${GODOT_TAG}).

Continuing with the user-level steps (pinned Godot download, venv, GUT): the
desktop image already ships the X11/Wayland/GL libraries the editor needs.

EOF
}

# ------------------------------------------------------------ Godot ---
fetch_godot_editor() {
	local os arch name sha dir archive bin
	os="$(host_os)" arch="$(host_arch)"
	[[ "${os}" != unsupported && "${arch}" != unsupported ]] ||
		die "no official Godot editor build for $(uname -s)/$(uname -m)"
	name="$(godot_archive_name)"
	sha="$(godot_archive_sha512)"
	dir="$(sf_cache_dir)/godot/${GODOT_TAG}"
	archive="${dir}/${name}"
	bin="$(godot_bin_path)"

	if [[ -x "${bin}" && -f "${archive}" ]] && verify_sha512 "${archive}" "${sha}" 2>/dev/null; then
		ok "Godot ${GODOT_TAG} editor already installed: ${bin}"
		return 0
	fi
	log "Fetching Godot ${GODOT_TAG} editor (${name})"
	run mkdir -p "${dir}"
	if [[ -f "${archive}" ]] && ! verify_sha512 "${archive}" "${sha}" 2>/dev/null; then
		warn "cached ${name} is corrupt or partial; downloading again"
		run rm -f "${archive}"
	fi
	[[ -f "${archive}" ]] || download "${GODOT_RELEASE_URL}/${name}" "${archive}"
	if [[ "${DRY_RUN}" == 0 ]]; then
		verify_sha512 "${archive}" "${sha}" || {
			rm -f "${archive}"
			die "Godot download did not match the pinned SHA-512 (deleted). Re-run; if it persists, do not proceed."
		}
		ok "SHA-512 verified"
	fi
	need_cmd unzip
	run unzip -o -q "${archive}" -d "${dir}"
	[[ "${DRY_RUN}" == 1 ]] || chmod +x "${bin}"
	ok "Godot editor: ${bin}"
}

fetch_godot_templates() {
	local dir name archive tdir marker
	dir="$(sf_cache_dir)/godot/${GODOT_TAG}"
	name="Godot_v${GODOT_TAG}_export_templates.tpz"
	archive="${dir}/${name}"
	tdir="$(godot_templates_dir)"
	marker="${tdir}/.${APP_SLUG}-verified"

	if [[ -f "${marker}" && "$(cat "${marker}")" == "${GODOT_SHA512_TEMPLATES}" ]]; then
		ok "export templates already installed: ${tdir}"
		return 0
	fi
	log "Fetching Godot ${GODOT_TAG} export templates (~1.3 GB, once)"
	run mkdir -p "${dir}"
	if [[ -f "${archive}" ]] && ! verify_sha512 "${archive}" "${GODOT_SHA512_TEMPLATES}" 2>/dev/null; then
		warn "cached ${name} is corrupt or partial; downloading again"
		run rm -f "${archive}"
	fi
	[[ -f "${archive}" ]] || download "${GODOT_RELEASE_URL}/${name}" "${archive}"
	if [[ "${DRY_RUN}" == 0 ]]; then
		verify_sha512 "${archive}" "${GODOT_SHA512_TEMPLATES}" || {
			rm -f "${archive}"
			die "export templates did not match the pinned SHA-512 (deleted)."
		}
		ok "SHA-512 verified"
	fi
	local staging="${dir}/templates-staging"
	run rm -rf "${staging}"
	run unzip -q "${archive}" -d "${staging}"
	run mkdir -p "${tdir}"
	run cp -a "${staging}/templates/." "${tdir}/"
	run rm -rf "${staging}"
	if [[ "${DRY_RUN}" == 0 ]]; then
		printf '%s' "${GODOT_SHA512_TEMPLATES}" >"${marker}"
	fi
	ok "export templates: ${tdir}"
}

# ------------------------------------------------------- python tools ---
setup_venv() {
	local venv="${SF_ROOT}/.venv" reqfile="${SF_ROOT}/requirements-dev.txt" stamp
	stamp="${venv}/.requirements.sha512"
	if ! have_cmd python3; then
		warn "python3 not found; skipping the lint venv (make lint will not work)."
		return 0
	fi
	if [[ -x "${venv}/bin/python" && -f "${stamp}" && "$(cat "${stamp}")" == "$(sha512_of "${reqfile}")" ]]; then
		ok "Python venv up to date: .venv"
		return 0
	fi
	log "Creating Python venv with pinned dev tools (.venv)"
	run python3 -m venv "${venv}" ||
		die "python3 -m venv failed. Install your distro's venv package (Debian/Ubuntu: python3-venv)."
	run "${venv}/bin/python" -m pip install --quiet --upgrade pip
	run "${venv}/bin/python" -m pip install --quiet -r "${reqfile}"
	[[ "${DRY_RUN}" == 1 ]] || sha512_of "${reqfile}" >"${stamp}"
	ok "Python venv: gdtoolkit, reuse, jsonschema, shellcheck"
}

# ---------------------------------------------------------------- GUT ---
fetch_gut() {
	local dest="${SF_GAME_DIR}/addons/gut" marker clone
	marker="${dest}/.pinned-commit"
	if [[ -f "${marker}" && "$(cat "${marker}")" == "${GUT_COMMIT}" ]]; then
		ok "GUT ${GUT_TAG} already present"
		return 0
	fi
	need_cmd git
	clone="$(sf_cache_dir)/gut-${GUT_TAG}"
	log "Fetching GUT ${GUT_TAG}"
	run rm -rf "${clone}"
	run git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${GUT_TAG}" "${GUT_REPO}" "${clone}" || {
		err "cloning ${GUT_REPO} failed. If behind an allow-list, allow: github.com"
		exit 1
	}
	if [[ "${DRY_RUN}" == 0 ]]; then
		local head
		head="$(git -C "${clone}" rev-parse HEAD)"
		[[ "${head}" == "${GUT_COMMIT}" ]] ||
			die "GUT tag ${GUT_TAG} resolved to ${head}, expected ${GUT_COMMIT}. Refusing to use it."
	fi
	run rm -rf "${dest}"
	run mkdir -p "${SF_GAME_DIR}/addons"
	run cp -a "${clone}/addons/gut" "${dest}"
	[[ "${DRY_RUN}" == 1 ]] || printf '%s' "${GUT_COMMIT}" >"${marker}"
	ok "GUT ${GUT_TAG} -> game/addons/gut"
}

# ---------------------------------------------------------------- main ---
main() {
	local family=''
	if [[ "$(host_os)" == linux ]]; then
		read_os_release || die "cannot read ${OS_RELEASE_FILE}; is this a Linux system?"
		log "Detected ${OS_PRETTY} (ID=${OS_ID}${OS_ID_LIKE:+, ID_LIKE=${OS_ID_LIKE}}${OS_VARIANT_ID:+, VARIANT_ID=${OS_VARIANT_ID}})"
		if is_immutable; then
			family=immutable
		else
			family="$(detect_family)"
		fi
	elif [[ "$(host_os)" == macos ]]; then
		family=macos
	else
		die "unsupported OS $(uname -s). Linux and macOS are supported for development."
	fi

	if [[ "${PRINT_DEPS}" == 1 ]]; then
		case "${family}" in
		pacman | apt | dnf | zypper | xbps | emerge)
			echo "family:   ${family}"
			echo "required: $(pkgs_required "${family}")"
			echo "optional: $(pkgs_optional "${family}")"
			;;
		*)
			echo "family:   ${family:-unknown}"
			print_generic_deps
			;;
		esac
		exit 0
	fi

	if [[ "${SKIP_PKGS}" == 0 ]]; then
		case "${family}" in
		pacman | apt | dnf | zypper | xbps | emerge) install_packages "${family}" ;;
		immutable) immutable_advice ;;
		nix)
			if [[ -z "${IN_NIX_SHELL:-}" ]]; then
				cat >&2 <<EOF

NixOS detected. System packages come from the flake's dev shell instead:
    nix develop          # then, inside the shell:
    ./scripts/bootstrap.sh
The dev shell provides an FHS environment so the official Godot binary runs.
EOF
				exit 0
			fi
			ok "inside nix develop; system packages provided by flake.nix"
			;;
		macos) log "macOS: no system packages needed for the Godot export (Xcode is required for iOS)." ;;
		*)
			err "Unrecognised distribution '${OS_ID:-?}' (ID_LIKE='${OS_ID_LIKE}')."
			print_generic_deps >&2
			cat >&2 <<'EOF'

Install the equivalents with your package manager, then run:
    scripts/bootstrap.sh --skip-packages
Patches adding your distro to scripts/bootstrap.sh are welcome.
EOF
			exit 0
			;;
		esac
	fi
	[[ "${PKGS_ONLY}" == 1 ]] && exit 0

	fetch_godot_editor
	[[ "${EDITOR_ONLY}" == 1 ]] || fetch_godot_templates
	[[ "${NO_VENV}" == 1 ]] || setup_venv
	[[ "${NO_GUT}" == 1 ]] || fetch_gut
	install_rapier_addon "${SF_GAME_DIR}/addons"

	echo >&2
	ok "bootstrap complete. Next: make run   (or: make test, make build)"
}

main "$@"
