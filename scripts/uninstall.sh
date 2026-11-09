#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Remove what scripts/install.sh installed, using its manifest, and
# optionally (--purge) the player's saves, castles and settings.
#
# Self-contained on purpose: install.sh also copies it to
# PREFIX/lib/<slug>/uninstall.sh (with identity.env beside it) so it still
# works after the repository or tarball is gone.
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${here}/identity.env" ]]; then
	# shellcheck source=/dev/null
	source "${here}/identity.env"
elif [[ -f "${here}/../app.env" ]]; then
	# shellcheck source=../app.env
	source "${here}/../app.env"
fi
: "${APP_NAME:?cannot find app.env or identity.env next to this script}" "${APP_SLUG:?}"

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
	c_red=$'\e[31m' c_yel=$'\e[33m' c_grn=$'\e[32m' c_blu=$'\e[34m' c_off=$'\e[0m'
else
	c_red='' c_yel='' c_grn='' c_blu='' c_off=''
fi
log() { printf '%s==>%s %s\n' "${c_blu}" "${c_off}" "$*" >&2; }
ok() { printf '%s ok%s %s\n' "${c_grn}" "${c_off}" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "${c_yel}" "${c_off}" "$*" >&2; }
die() {
	printf '%serror:%s %s\n' "${c_red}" "${c_off}" "$*" >&2
	exit 1
}
DRY_RUN=0
run() {
	if [[ "${DRY_RUN}" == 1 ]]; then
		printf '[dry-run] %s\n' "$*" >&2
		return 0
	fi
	"$@"
}

usage() {
	cat <<EOF
Usage: uninstall.sh [options]

Removes ${APP_NAME} files listed in the install manifest. Your saves, castles
and settings are kept unless you add --purge.

  --prefix DIR   where it was installed (default: ~/.local)
  --system       it was installed with --system (/usr/local; uses sudo)
  --purge        also delete saves, castles and settings:
                   ${XDG_DATA_HOME:-~/.local/share}/${APP_SLUG}
                   ${XDG_CONFIG_HOME:-~/.config}/${APP_SLUG}
                   ${XDG_CACHE_HOME:-~/.cache}/${APP_SLUG}
  -y, --yes      do not ask before --purge deletes anything
  -n, --dry-run  print what would be removed
  -h, --help     this text
EOF
}

PREFIX="${HOME}/.local"
SYSTEM=0
PURGE=0
YES=0
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
	--purge) PURGE=1 ;;
	-y | --yes) YES=1 ;;
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

SUDO=()
if [[ "$(id -u)" != 0 && (${SYSTEM} == 1 || ! -w "${PREFIX}") && -d "${PREFIX}" ]]; then
	command -v sudo >/dev/null 2>&1 || die "${PREFIX} is not writable and sudo is not available"
	SUDO=(sudo)
fi

MANIFEST="${PREFIX}/lib/${APP_SLUG}/.install-manifest"
removed=0
if [[ -f "${MANIFEST}" ]]; then
	log "Removing ${APP_NAME} from ${PREFIX}"
	while IFS= read -r rel; do
		[[ -n "${rel}" ]] || continue
		# Only plain relative paths inside PREFIX; never follow '..'.
		case "/${rel}/" in
		*/../* | *//*) die "refusing suspicious manifest entry '${rel}'" ;;
		esac
		[[ "${rel}" != /* ]] || die "refusing absolute manifest entry '${rel}'"
		target="${PREFIX}/${rel}"
		if [[ -L "${target}" || -f "${target}" ]]; then
			run "${SUDO[@]}" rm -f "${target}"
			removed=$((removed + 1))
		fi
	done <"${MANIFEST}"
	# Folders that only this game uses, deepest first, if now empty.
	for d in "lib/${APP_SLUG}" "share/doc/${APP_SLUG}" "share/licenses/${APP_SLUG}"; do
		if [[ -d "${PREFIX}/${d}" ]]; then
			run "${SUDO[@]}" rmdir --ignore-fail-on-non-empty "${PREFIX}/${d}"
		fi
	done
	if command -v update-desktop-database >/dev/null 2>&1 && [[ -d "${PREFIX}/share/applications" ]]; then
		run "${SUDO[@]}" update-desktop-database -q "${PREFIX}/share/applications" || true
	fi
	if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -f "${PREFIX}/share/icons/hicolor/index.theme" ]]; then
		run "${SUDO[@]}" gtk-update-icon-cache -q -t -f "${PREFIX}/share/icons/hicolor" || true
	fi
	ok "removed ${removed} file(s) from ${PREFIX}"
else
	log "${APP_NAME} is not installed in ${PREFIX} (no ${MANIFEST#"${PREFIX}"/}); nothing to remove"
fi

if [[ "${PURGE}" == 1 ]]; then
	data=(
		"${XDG_DATA_HOME:-${HOME}/.local/share}/${APP_SLUG}"
		"${XDG_CONFIG_HOME:-${HOME}/.config}/${APP_SLUG}"
		"${XDG_CACHE_HOME:-${HOME}/.cache}/${APP_SLUG}"
	)
	present=()
	for d in "${data[@]}"; do
		[[ -e "${d}" ]] && present+=("${d}")
	done
	if [[ ${#present[@]} -eq 0 ]]; then
		log "no saves, castles or settings to delete"
	else
		log "--purge will delete your saves, castles and settings:"
		printf '  %s\n' "${present[@]}" >&2
		if [[ "${YES}" != 1 && "${DRY_RUN}" != 1 ]]; then
			[[ -t 0 ]] || die "not deleting without confirmation; add --yes to purge non-interactively"
			read -r -p "Delete them for good? [y/N] " answer
			[[ "${answer}" == [yY]* ]] || die "kept your data; nothing deleted"
		fi
		for d in "${present[@]}"; do
			run rm -rf -- "${d}"
		done
		ok "deleted ${#present[@]} folder(s) of player data"
	fi
fi
