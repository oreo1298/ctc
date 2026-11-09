# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Staging helpers shared by build.sh, package.sh and install.sh: render the
# packaging templates from app.env, and lay out an installed file tree.
# Source after common.sh and load_identity.
# shellcheck disable=SC2154 # SF_*, APP_* and GODOT_* come from common.sh and app.env

SF_PACKAGING="${SF_ROOT}/packaging"
SF_BUILD="${SF_BUILD:-${SF_ROOT}/build}"
SF_EXPORT="${SF_EXPORT:-${SF_BUILD}/export}"
ICON_SIZES=(16 24 32 48 64 128 256 512)
# Rendered too, for the iOS app icon (used by build.sh).
# shellcheck disable=SC2034
APP_ICON_EXTRA=(1024)

# Versions per format, from APP_VERSION (SemVer: 1.0.0 or 1.0.0-rc.1).
# rpm and pacman forbid '-'; deb and rpm sort '~' before the release; pacman
# sorts a trailing letter segment before it; Windows and iOS want numbers.
version_numeric() { printf '%s' "${APP_VERSION%%-*}"; }
version_tilde() { printf '%s' "${APP_VERSION/-/\~}"; }
version_pacman() {
	local base="${APP_VERSION%%-*}" pre
	pre="${APP_VERSION#"${base}"}"
	pre="${pre#-}"
	printf '%s%s' "${base}" "${pre//./}"
}
is_prerelease() { [[ "${APP_VERSION}" == *-* ]]; }

# The build's architecture names: x86_64 / arm64 (Godot), and the packaging
# names other tools want.
deb_arch() { case "$1" in x86_64) echo amd64 ;; arm64) echo arm64 ;; esac; }
rpm_arch() { case "$1" in x86_64) echo x86_64 ;; arm64) echo aarch64 ;; esac; }

# Release date: SOURCE_DATE_EPOCH, else the last commit, else today.
release_date() {
	if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
		date -u -d "@${SOURCE_DATE_EPOCH}" +%F
	elif git -C "${SF_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
		git -C "${SF_ROOT}" log -1 --format=%cs
	else
		date -u +%F
	fi
}

# Escape a value for a sed s||| replacement; newlines become \n (GNU sed).
_sed_esc() {
	local v
	v="$(printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g')"
	printf '%s' "${v//$'\n'/\\n}"
}

# render_template IN OUT [KEY=VALUE...]
# Replaces @APP_*@ (from app.env) and any extra @KEY@ given. Fails if a
# placeholder is left over, so a typo never ships.
render_template() {
	local in="$1" out="$2" kv
	shift 2
	local base="${APP_HOMEPAGE/https:\/\/github.com/https://raw.githubusercontent.com}/main/docs/screenshots"
	local -a pairs=(
		"APP_NAME=${APP_NAME}" "APP_ID=${APP_ID}" "APP_SLUG=${APP_SLUG}"
		"APP_VERSION=${APP_VERSION}" "APP_SUMMARY=${APP_SUMMARY}"
		"APP_HOMEPAGE=${APP_HOMEPAGE}" "APP_DEVELOPER=${APP_DEVELOPER}"
		"APP_DEVELOPER_ID=${APP_DEVELOPER_ID}" "APP_CONTACT=${APP_CONTACT}"
		"SCREENSHOT_BASE=${base}"
		"RELEASE_DATE=$(release_date)" "YEAR=$(release_date | cut -c1-4)"
		"GODOT_VERSION=${GODOT_VERSION}" "GODOT_TAG=${GODOT_TAG}"
		"APP_SLUG_UPPER=${APP_SLUG^^}"
		"VERSION_NUM=$(version_numeric)" "VERSION_TILDE=$(version_tilde)"
		"VERSION_PACMAN=$(version_pacman)"
		"RELEASE_TYPE=$(is_prerelease && echo development || echo stable)"
		"$@"
	)
	local -a sed_args=()
	for kv in "${pairs[@]}"; do
		sed_args+=(-e "s|@${kv%%=*}@|$(_sed_esc "${kv#*=}")|g")
	done
	if [[ "${DRY_RUN}" == 1 ]]; then
		run sed "${sed_args[@]}" "${in}"
		return 0
	fi
	mkdir -p "$(dirname "${out}")"
	sed "${sed_args[@]}" "${in}" >"${out}"
	if grep -nE '@[A-Z][A-Z0-9_]*@' "${out}" >&2; then
		die "unrendered placeholder in ${out} (from ${in#"${SF_ROOT}"/})"
	fi
}

# export_dir ARCH -> build/export/linux-ARCH
export_dir() { printf '%s/linux-%s' "${SF_EXPORT}" "$1"; }

# require_export ARCH -- the Linux export for ARCH must exist.
require_export() {
	local dir
	dir="$(export_dir "$1")"
	[[ "${DRY_RUN}" == 1 || -x "${dir}/${APP_SLUG}" ]] ||
		die "no Linux $1 build in ${dir#"${SF_ROOT}"/}. Run: make build ARGS='--target linux-$1'"
}

# stage_linux ARCH DESTDIR PREFIX
# Lay out an installed tree for PREFIX (e.g. /usr) inside DESTDIR:
#   PREFIX/lib/SLUG/{SLUG,*.so}  PREFIX/bin/SLUG -> ../lib/SLUG/SLUG
#   PREFIX/share/{applications,metainfo,icons/hicolor,man/man6,doc/SLUG,
#                 licenses/SLUG}
stage_linux() {
	local arch="$1" dest="$2" prefix="$3" src root size
	src="$(export_dir "${arch}")"
	require_export "${arch}"
	root="${dest}${prefix}"
	run mkdir -p "${root}/bin" "${root}/lib/${APP_SLUG}" "${root}/share/applications" \
		"${root}/share/man/man6" \
		"${root}/share/metainfo" "${root}/share/doc/${APP_SLUG}" \
		"${root}/share/licenses/${APP_SLUG}" "${root}/share/icons/hicolor/scalable/apps"
	run install -m 0755 "${src}/${APP_SLUG}" "${root}/lib/${APP_SLUG}/${APP_SLUG}"
	local so
	for so in "${src}"/*.so; do
		[[ -e "${so}" ]] || continue
		run install -m 0755 "${so}" "${root}/lib/${APP_SLUG}/"
	done
	if [[ -f "${src}/${APP_SLUG}.pck" ]]; then
		run install -m 0644 "${src}/${APP_SLUG}.pck" "${root}/lib/${APP_SLUG}/"
	fi
	run ln -sfn "../lib/${APP_SLUG}/${APP_SLUG}" "${root}/bin/${APP_SLUG}"
	render_template "${SF_PACKAGING}/linux/app.desktop.in" \
		"${root}/share/applications/${APP_ID}.desktop"
	render_template "${SF_PACKAGING}/linux/app.metainfo.xml.in" \
		"${root}/share/metainfo/${APP_ID}.metainfo.xml"
	render_template "${SF_PACKAGING}/linux/app.6.in" "${root}/share/man/man6/${APP_SLUG}.6"
	run gzip -9nf "${root}/share/man/man6/${APP_SLUG}.6"
	for size in "${ICON_SIZES[@]}"; do
		run mkdir -p "${root}/share/icons/hicolor/${size}x${size}/apps"
		run install -m 0644 "${SF_BUILD}/icons/${size}.png" \
			"${root}/share/icons/hicolor/${size}x${size}/apps/${APP_ID}.png"
	done
	run install -m 0644 "${SF_GAME_DIR}/icon.svg" \
		"${root}/share/icons/hicolor/scalable/apps/${APP_ID}.svg"
	local f
	for f in README.md CHANGELOG.md CREDITS.md; do
		run install -m 0644 "${SF_ROOT}/${f}" "${root}/share/doc/${APP_SLUG}/${f}"
	done
	run install -m 0644 "${SF_ROOT}/LICENSE" "${root}/share/licenses/${APP_SLUG}/LICENSE"
	for f in "${SF_ROOT}"/LICENSES/*.txt; do
		run install -m 0644 "${f}" "${root}/share/licenses/${APP_SLUG}/$(basename "${f}")"
	done
	run install -m 0644 "${src}/THIRD-PARTY-NOTICES.txt" \
		"${root}/share/licenses/${APP_SLUG}/THIRD-PARTY-NOTICES.txt"
}
