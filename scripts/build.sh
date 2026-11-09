#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Headless exports of the game with the pinned Godot and export templates.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity
# shellcheck source=lib/stage.sh
source "${SF_ROOT}/scripts/lib/stage.sh"

usage() {
	cat <<EOF
Usage: scripts/build.sh [--target T]... [options]

Exports ${APP_NAME} ${APP_VERSION} into build/export/<target>/:
  linux-x86_64     ${APP_SLUG} (pck embedded) + Rapier .so
  linux-arm64      same, for 64-bit ARM (e.g. Asahi on Apple silicon)
  windows-x86_64   ${APP_NAME}.exe (pck embedded) + Rapier .dll
  ios              Xcode project (build it on a Mac: see docs/IOS.md)
Also renders the icons (build/icons) and writes THIRD-PARTY-NOTICES.txt.

  --target T       one of the above, 'linux' (both Linux), or 'all'.
                   Repeatable. Default: Linux for this machine.
  --debug          export debug templates instead of release
  --no-embed-pck   keep the .pck next to the binary (used by the Nix package)
  --godot PATH     Godot editor binary (default: the pinned one, or \$GODOT)
  --templates DIR  export templates folder (default: Godot's own folder,
                   $(godot_templates_dir))
  -n, --dry-run    print what would run
  -h, --help       this text

Environment: SF_IOS_TEAM_ID  your Apple Developer team (10 characters) for
the iOS project; without it the project is unsigned (see docs/IOS.md).
EOF
}

TARGETS=()
MODE="release"
EMBED="true"
TEMPLATES="${SF_TEMPLATES_DIR:-}"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--target)
		[[ $# -ge 2 ]] || die "--target needs a value (see --help)"
		TARGETS+=("$2")
		shift
		;;
	--target=*) TARGETS+=("${1#*=}") ;;
	--debug) MODE="debug" ;;
	--no-embed-pck) EMBED="false" ;;
	--godot)
		[[ $# -ge 2 ]] || die "--godot needs a path"
		GODOT="$2"
		shift
		;;
	--templates)
		[[ $# -ge 2 ]] || die "--templates needs a folder"
		TEMPLATES="$2"
		shift
		;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
	[[ "$(host_arch)" != unsupported ]] || die "no default target for $(uname -m); pass --target"
	TARGETS=("linux-$(host_arch)")
fi
expanded=()
for t in "${TARGETS[@]}"; do
	case "${t}" in
	all) expanded+=(linux-x86_64 linux-arm64 windows-x86_64 ios) ;;
	linux) expanded+=(linux-x86_64 linux-arm64) ;;
	linux-x86_64 | linux-arm64 | windows-x86_64 | ios) expanded+=("${t}") ;;
	*) die "unknown target '${t}' (see --help)" ;;
	esac
done
# Unique, keeping the order given.
mapfile -t TARGETS < <(printf '%s\n' "${expanded[@]}" | awk '!seen[$0]++')

godot="$(resolve_godot)"
[[ -n "${TEMPLATES}" ]] || TEMPLATES="$(godot_templates_dir)"
need_cmd python3

preset_of() {
	case "$1" in
	linux-x86_64) echo "Linux x86_64" ;;
	linux-arm64) echo "Linux arm64" ;;
	windows-x86_64) echo "Windows x86_64" ;;
	ios) echo "iOS" ;;
	esac
}
template_of() {
	case "$1" in
	linux-x86_64) echo "linux_${MODE}.x86_64" ;;
	linux-arm64) echo "linux_${MODE}.arm64" ;;
	windows-x86_64) echo "windows_${MODE}_x86_64.exe" ;;
	ios) echo "ios.zip" ;;
	esac
}
binary_of() {
	case "$1" in
	linux-*) echo "${APP_SLUG}" ;;
	windows-*) echo "${APP_NAME}.exe" ;;
	ios) echo "${APP_NAME}.ipa" ;;
	esac
}

# ------------------------------------------------------------- preflight ---
for t in "${TARGETS[@]}"; do
	tpl="${TEMPLATES}/$(template_of "${t}")"
	if [[ "${DRY_RUN}" == 0 && ! -f "${tpl}" ]]; then
		err "export template missing: ${tpl}"
		die "run 'make dev' (without --editor-only) to fetch the pinned templates, or pass --templates DIR"
	fi
done
[[ "${DRY_RUN}" == 1 || -f "${SF_GAME_DIR}/addons/godot-rapier2d/.pinned-sha256" ]] ||
	die "godot-rapier is not installed in game/addons. Run 'make dev' first."

# godot_run LOG ARGS... -- exports are chatty: keep the output in a log and
# show its tail only when Godot fails.
godot_run() {
	local log_file="$1"
	shift
	if [[ "${DRY_RUN}" == 1 ]]; then
		run "${godot}" "$@"
		return 0
	fi
	if ! "${godot}" "$@" >"${log_file}" 2>&1; then
		tail -n 40 "${log_file}" >&2
		die "Godot failed (full log: ${log_file#"${SF_ROOT}"/})"
	fi
}

run mkdir -p "${SF_BUILD}/logs" "${SF_BUILD}/icons" "${SF_EXPORT}"

# ----------------------------------------------------------------- icons ---
log "Rendering icons"
godot_run "${SF_BUILD}/logs/icons.log" --headless --path "${SF_GAME_DIR}" \
	-s res://tools/render_icon.gd -- "${SF_GAME_DIR}/icon.svg" "${SF_BUILD}/icons" \
	"${ICON_SIZES[@]}" "${APP_ICON_EXTRA[@]}"
ico_pngs=()
for s in 16 24 32 48 64 128 256; do
	ico_pngs+=("${SF_BUILD}/icons/${s}.png")
done
run python3 -I "${SF_ROOT}/tools/make_ico.py" "${SF_BUILD}/icons/${APP_SLUG}.ico" "${ico_pngs[@]}"

# --------------------------------------------------------------- presets ---
# iOS: Godot wants an Apple team even for an unsigned Xcode project. Without
# SF_IOS_TEAM_ID a placeholder is used; pick your own team in Xcode.
IOS_TEAM_ID="${SF_IOS_TEAM_ID:-UNSIGNED00}"
render_template "${SF_PACKAGING}/godot/export_presets.cfg.in" \
	"${SF_GAME_DIR}/export_presets.cfg" \
	"TEMPLATES=${TEMPLATES}" "EMBED_PCK=${EMBED}" "ICON_ICO=${SF_BUILD}/icons/${APP_SLUG}.ico" \
	"ICON_1024=${SF_BUILD}/icons/1024.png" "IOS_TEAM_ID=${IOS_TEAM_ID}"

log "Importing project"
godot_run "${SF_BUILD}/logs/import.log" --headless --path "${SF_GAME_DIR}" --import

notices="${SF_BUILD}/THIRD-PARTY-NOTICES.txt"
godot_run "${SF_BUILD}/logs/licenses.log" --headless --path "${SF_GAME_DIR}" \
	-s res://tools/dump_licenses.gd -- "${notices}"
if [[ "${DRY_RUN}" == 0 ]]; then
	rapier="${SF_GAME_DIR}/addons/godot-rapier2d"
	{
		printf '\n\ngodot-rapier %s (physics, https://github.com/appsinacup/godot-rapier-physics)\n' \
			"${RAPIER_VERSION}"
		printf '%s\n' "========================================================================"
		cat "${rapier}/LICENSE"
		if [[ -f "${rapier}/THIRDPARTY.txt" ]]; then
			printf '\n'
			cat "${rapier}/THIRDPARTY.txt"
		fi
	} >>"${notices}"
fi

# --------------------------------------------------------------- exports ---
for t in "${TARGETS[@]}"; do
	out="${SF_EXPORT}/${t}"
	bin="$(binary_of "${t}")"
	log "Exporting ${t} (${MODE})"
	run rm -rf "${out}"
	run mkdir -p "${out}"
	godot_run "${SF_BUILD}/logs/export-${t}.log" --headless --path "${SF_GAME_DIR}" \
		"--export-${MODE}" "$(preset_of "${t}")" "${out}/${bin}"
	if [[ "${DRY_RUN}" == 0 && "${t}" == ios ]]; then
		[[ -d "${out}/${APP_NAME}.xcodeproj" ]] ||
			die "export produced no Xcode project (see build/logs/export-ios.log)"
		[[ -n "$(find "${out}" -name 'libgodot_rapier.ios*' -print -quit)" ]] ||
			die "the iOS project is missing the Rapier framework (see build/logs/export-ios.log)"
		cp "${notices}" "${out}/THIRD-PARTY-NOTICES.txt"
		ok "ios: ${out#"${SF_ROOT}"/}/${APP_NAME}.xcodeproj (build it on a Mac, see docs/IOS.md)"
	elif [[ "${DRY_RUN}" == 0 ]]; then
		[[ -s "${out}/${bin}" ]] || die "export produced no ${bin} (see build/logs/export-${t}.log)"
		have_rapier=0
		for lib in "${out}"/libgodot_rapier*; do
			[[ -e "${lib}" ]] && have_rapier=1
		done
		[[ "${have_rapier}" == 1 ]] ||
			die "export of ${t} is missing the Rapier library (see build/logs/export-${t}.log)"
		[[ "${t}" == windows-* ]] || chmod 0755 "${out}/${bin}"
		cp "${notices}" "${out}/THIRD-PARTY-NOTICES.txt"
		{
			printf 'name=%s\nversion=%s\ntarget=%s\nmode=%s\ngodot=%s\n' \
				"${APP_NAME}" "${APP_VERSION}" "${t}" "${MODE}" "${GODOT_TAG}"
			printf 'commit=%s\n' "$(git -C "${SF_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
		} >"${out}/BUILD_INFO"
		ok "${t}: ${out#"${SF_ROOT}"/}/${bin} ($(du -h "${out}/${bin}" | cut -f1))"
	fi
done
