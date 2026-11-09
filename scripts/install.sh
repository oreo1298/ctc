#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Install the game for this user (default ~/.local) or system-wide. Works
# from the repository (after `make build`) and from the portable tarball.
# Every file it writes is listed in a manifest, so re-running upgrades in
# place and scripts/uninstall.sh removes exactly what was added.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity
# shellcheck source=lib/stage.sh
source "${SF_ROOT}/scripts/lib/stage.sh"

usage() {
	cat <<EOF
Usage: scripts/install.sh [options]

Installs ${APP_NAME} ${APP_VERSION}: the game, a menu entry, icons and AppStream
metadata. Nothing is downloaded and nothing outside PREFIX is touched.

  --prefix DIR   install under DIR (default: ~/.local, no root needed)
  --system       install under /usr/local for every user (uses sudo)
  --arch A       x86_64 or arm64 (default: this machine)
  --destdir DIR  packagers: stage into DIR/PREFIX without a manifest or
                 menu cache refresh (e.g. PKGBUILD: --prefix /usr --destdir "\$pkgdir")
  -n, --dry-run  print what would happen
  -h, --help     this text

Remove it again with scripts/uninstall.sh (same --prefix / --system).
EOF
}

PREFIX="${HOME}/.local"
DESTDIR=""
ARCH="$(host_arch)"
SYSTEM=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--prefix)
		[[ $# -ge 2 ]] || die "--prefix needs a folder"
		PREFIX="$2"
		shift
		;;
	--prefix=*) PREFIX="${1#*=}" ;;
	--system)
		SYSTEM=1
		PREFIX="/usr/local"
		;;
	--arch)
		[[ $# -ge 2 ]] || die "--arch needs a value"
		ARCH="$2"
		shift
		;;
	--destdir)
		[[ $# -ge 2 ]] || die "--destdir needs a folder"
		DESTDIR="$2"
		shift
		;;
	--destdir=*) DESTDIR="${1#*=}" ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done

[[ "${PREFIX}" == /* ]] || die "--prefix must be an absolute path (got '${PREFIX}')"
PREFIX="${PREFIX%/}"
case "${ARCH}" in
x86_64 | arm64) ;;
*) die "unsupported architecture '${ARCH}' (x86_64 or arm64)" ;;
esac

# ------------------------------------------------------------- payload ---
# The portable tarball carries a ready tree in files/; in the repository we
# stage one from build/export.
if [[ -d "${SF_ROOT}/files" ]]; then
	PAYLOAD="${SF_ROOT}/files"
	[[ -f "${SF_ROOT}/files/lib/${APP_SLUG}/${APP_SLUG}" ]] || die "this tarball is incomplete: files/lib/${APP_SLUG}/${APP_SLUG} is missing"
	tar_arch="$(sed -n 's/^target=linux-//p' "${SF_ROOT}/files/lib/${APP_SLUG}/BUILD_INFO" 2>/dev/null || true)"
	if [[ -n "${tar_arch}" && "${tar_arch}" != "${ARCH}" ]]; then
		die "this tarball is for ${tar_arch}, but this machine is ${ARCH}. Download the linux-${ARCH} tarball instead."
	fi
else
	PAYLOAD="${SF_BUILD}/stage/linux-${ARCH}"
	log "Staging the linux-${ARCH} build"
	run rm -rf "${PAYLOAD}"
	stage_linux "${ARCH}" "${PAYLOAD}" ""
	run install -m 0644 "$(export_dir "${ARCH}")/BUILD_INFO" "${PAYLOAD}/lib/${APP_SLUG}/BUILD_INFO"
fi

# ------------------------------------------------------- packaging mode ---
if [[ -n "${DESTDIR}" ]]; then
	run mkdir -p "${DESTDIR}${PREFIX}"
	run cp -a "${PAYLOAD}/." "${DESTDIR}${PREFIX}/"
	ok "staged into ${DESTDIR}${PREFIX}"
	exit 0
fi

# --------------------------------------------------------------- privileges ---
SUDO=()
probe="${PREFIX}"
while [[ ! -e "${probe}" ]]; do probe="$(dirname "${probe}")"; done
if [[ ! -w "${probe}" ]]; then
	[[ "$(id -u)" != 0 ]] || die "cannot write to ${probe}"
	need_cmd sudo
	SUDO=(sudo)
	log "${PREFIX} is not writable by you; using sudo"
elif [[ "${SYSTEM}" == 1 && "$(id -u)" != 0 ]]; then
	SUDO=(sudo)
fi
as_root() { run "${SUDO[@]}" "$@"; }

MANIFEST="${PREFIX}/lib/${APP_SLUG}/.install-manifest"

# ---------------------------------------------------------------- upgrade ---
if [[ -f "${MANIFEST}" ]]; then
	log "Removing the previous install in ${PREFIX} first"
	uninstall_args=(--prefix "${PREFIX}")
	[[ "${DRY_RUN}" == 1 ]] && uninstall_args+=(--dry-run)
	"${SF_ROOT}/scripts/uninstall.sh" "${uninstall_args[@]}"
fi

# ---------------------------------------------------------------- install ---
log "Installing ${APP_NAME} ${APP_VERSION} (${ARCH}) into ${PREFIX}"
manifest_tmp="$(mktemp)"
trap 'rm -f "${manifest_tmp}"' EXIT
desktop_rel="share/applications/${APP_ID}.desktop"
while IFS= read -r -d '' path; do
	rel="${path#"${PAYLOAD}"/}"
	dest="${PREFIX}/${rel}"
	as_root mkdir -p "$(dirname "${dest}")"
	if [[ -L "${path}" ]]; then
		as_root ln -sfn "$(readlink "${path}")" "${dest}"
	elif [[ "${rel}" == "${desktop_rel}" && "${PREFIX}" != /usr ]]; then
		# Outside /usr the bin folder may not be on the menu's PATH: point
		# the launcher at the installed binary itself.
		tmp_desktop="$(mktemp)"
		sed -e "s|^Exec=.*|Exec=${PREFIX}/bin/${APP_SLUG}|" \
			-e "/^Exec=/a TryExec=${PREFIX}/bin/${APP_SLUG}" "${path}" >"${tmp_desktop}"
		as_root install -m 0644 "${tmp_desktop}" "${dest}"
		rm -f "${tmp_desktop}"
	else
		as_root install -m "$(stat -c '%a' "${path}")" "${path}" "${dest}"
	fi
	printf '%s\n' "${rel}" >>"${manifest_tmp}"
done < <(find "${PAYLOAD}" \( -type f -o -type l \) -print0 | sort -z)
# A copy of the uninstaller that keeps working once this folder is gone.
identity_tmp="$(mktemp)"
printf 'APP_NAME=%q\nAPP_ID=%q\nAPP_SLUG=%q\nAPP_VERSION=%q\n' \
	"${APP_NAME}" "${APP_ID}" "${APP_SLUG}" "${APP_VERSION}" >"${identity_tmp}"
as_root install -m 0644 "${identity_tmp}" "${PREFIX}/lib/${APP_SLUG}/identity.env"
rm -f "${identity_tmp}"
as_root install -m 0755 "${SF_ROOT}/scripts/uninstall.sh" "${PREFIX}/lib/${APP_SLUG}/uninstall.sh"
printf '%s\n' "lib/${APP_SLUG}/identity.env" "lib/${APP_SLUG}/uninstall.sh" \
	"lib/${APP_SLUG}/.install-manifest" >>"${manifest_tmp}"
as_root install -m 0644 "${manifest_tmp}" "${MANIFEST}"

# --------------------------------------------------------- desktop caches ---
if have_cmd update-desktop-database; then
	as_root update-desktop-database -q "${PREFIX}/share/applications" || true
fi
if have_cmd gtk-update-icon-cache && [[ -f "${PREFIX}/share/icons/hicolor/index.theme" ]]; then
	as_root gtk-update-icon-cache -q -t -f "${PREFIX}/share/icons/hicolor" || true
fi

ok "installed ${APP_NAME} ${APP_VERSION} into ${PREFIX}"
case ":${PATH}:" in
*":${PREFIX}/bin:"*) log "Start it from your app menu, or run: ${APP_SLUG}" ;;
*)
	log "Start it from your app menu, or run: ${PREFIX}/bin/${APP_SLUG}"
	warn "${PREFIX}/bin is not on your PATH, so plain '${APP_SLUG}' won't work in a terminal yet."
	;;
esac
log "Remove it with: ${PREFIX}/lib/${APP_SLUG}/uninstall.sh$([[ "${PREFIX}" == "${HOME}/.local" ]] || printf ' --prefix %q' "${PREFIX}")"
