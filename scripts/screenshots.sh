#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Render key scenes to PNG with Xvfb + Mesa (llvmpipe) + the Compatibility
# renderer, i.e. the "low" quality tier. Used to review art without a screen.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

OUT="${SF_ROOT}/build/screenshots"
SIZE="1280x720"
ONLY=""

usage() {
	cat <<EOF
Usage: scripts/screenshots.sh [--out DIR] [--size WxH] [--only NAME] [--dry-run]

Renders these scenes to DIR (default build/screenshots/):
  menu        title screen
  levels      level select (all unlocked)
  settings    settings screen
  aim         level 1 at rest, aiming
  swing       mid-swing
  flight      projectile in the air (camera following)
  impact      the moment of impact
  collapse    the collapse framed by the camera
  win         win card with medal
  pause       the pause menu
  materials   every material, heavily cracked
  shatter     every material breaking at once
  fire        flammable materials burning (fire spread, charring)
  editor      castle editor with a block selected
  terrain     castle editor, ground tool
  share       castle editor, share dialog
  testplay    a castle won in the editor's test-play
Needs Xvfb and Mesa (installed by scripts/bootstrap.sh).
  --update-docs  also refresh the matching PNGs in docs/screenshots/
EOF
}
UPDATE_DOCS=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--out)
		OUT="$2"
		shift
		;;
	--size)
		SIZE="$2"
		shift
		;;
	--only)
		ONLY="$2"
		shift
		;;
	--update-docs) UPDATE_DOCS=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done

need_cmd Xvfb
godot="$(resolve_godot)"
run mkdir -p "${OUT}"

display=""
xvfb_pid=""
start_xvfb() {
	local n
	for n in $(seq 90 120); do
		if [[ ! -e "/tmp/.X${n}-lock" ]]; then
			display=":${n}"
			break
		fi
	done
	[[ -n "${display}" ]] || die "no free X display number found"
	if [[ "${DRY_RUN}" == 1 ]]; then
		run Xvfb "${display}" -screen 0 "${SIZE}x24" -nolisten tcp
		return 0
	fi
	Xvfb "${display}" -screen 0 "${SIZE}x24" -nolisten tcp >/dev/null 2>&1 &
	xvfb_pid=$!
	sleep 1
	kill -0 "${xvfb_pid}" 2>/dev/null || die "Xvfb failed to start"
}
cleanup() {
	if [[ -n "${xvfb_pid}" ]]; then
		kill "${xvfb_pid}" 2>/dev/null || true
	fi
}
trap cleanup EXIT

# shot NAME SECONDS USER_ARGS...
shot() {
	local name="$1" quit="$2"
	shift 2
	[[ -z "${ONLY}" || "${ONLY}" == "${name}" ]] || return 0
	log "rendering ${name}"
	local w="${SIZE%x*}" h="${SIZE#*x}"
	run env DISPLAY="${display}" LIBGL_ALWAYS_SOFTWARE=1 "${godot}" \
		--path "${SF_GAME_DIR}" --rendering-method gl_compatibility --display-driver x11 \
		--resolution "${w}x${h}" --fixed-fps 60 --audio-driver Dummy -- \
		--no-save --quit-after="${quit}" "$@" >"${OUT}/${name}.log" 2>&1 || true
	[[ "${DRY_RUN}" == 1 || -f "${OUT}/${name}.png" ]] || warn "${name}: no image (see ${OUT}/${name}.log)"
}

start_xvfb
L=(--level=greenmantle-01)
shot menu 2.0 --screenshots="1.8:${OUT}/menu.png"
shot levels 2.0 --screen=levels --unlock-all --screenshots="1.8:${OUT}/levels.png"
shot settings 2.0 --screen=settings --screenshots="1.8:${OUT}/settings.png"
shot aim 3.0 "${L[@]}" --no-intro --screenshots="2.6:${OUT}/aim.png"
# The level-1 gold shot is a flat release at phase 0.65.
shot swing 2.0 "${L[@]}" --autoplay=0.99 --screenshots="1.45:${OUT}/swing.png"
shot flight 3.0 "${L[@]}" --autoplay=0.65 --screenshots="2.55:${OUT}/flight.png"
shot impact 4.0 "${L[@]}" --autoplay=0.65 --screenshots="3.45:${OUT}/impact.png"
shot collapse 5.5 "${L[@]}" --autoplay=0.65 --screenshots="4.9:${OUT}/collapse.png"
shot win 8.0 "${L[@]}" --autoplay=0.65 --screenshots="7.5:${OUT}/win.png"
shot pause 2.0 "${L[@]}" --no-intro --debug-pause --screenshots="1.6:${OUT}/pause.png"
# Every material: cracked, then all breaking at once.
M=(--level=dev-materials --camera=castle --no-intro)
shot materials 2.2 "${M[@]}" --debug-damage=0.7 --screenshots="2.0:${OUT}/materials.png"
shot shatter 2.0 "${M[@]}" --debug-damage=1.0 --screenshots="1.25:${OUT}/shatter.png"
shot fire 4.2 "${M[@]}" --debug-ignite --screenshots="4.0:${OUT}/fire.png"

E=(--screen=editor --edit=greenmantle-06)
shot editor 2.4 "${E[@]}" --edit-select=4 --screenshots="2.2:${OUT}/editor.png"
shot terrain 2.4 "${E[@]}" --edit-tool=terrain --screenshots="2.2:${OUT}/terrain.png"
shot share 2.4 "${E[@]}" --edit-dialog=share --screenshots="2.2:${OUT}/share.png"
shot testplay 9.0 --screen=editor --edit=greenmantle-01 --edit-test --autoplay=0.65 \
	--screenshots="8.4:${OUT}/testplay.png"

if [[ "${UPDATE_DOCS}" == 1 ]]; then
	# Refresh the images the docs already use; never add stray renders.
	for doc in "${SF_ROOT}"/docs/screenshots/*.png; do
		name="$(basename "${doc}")"
		[[ -f "${OUT}/${name}" ]] && run cp "${OUT}/${name}" "${doc}"
	done
fi
ok "screenshots in ${OUT#"${SF_ROOT}"/}"
