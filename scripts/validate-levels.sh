#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Run the level-validator bot over the campaign (docs/DESIGN.md §6.4).
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

MODE="replay"
JOBS="$(nproc 2>/dev/null || echo 2)"
ONLY=""
WRITE=0
OUT="${SF_ROOT}/build/validator"

usage() {
	cat <<EOF
Usage: scripts/validate-levels.sh [--mode MODE] [--jobs N] [--only ID[,ID]] [--write] [--dry-run]

Modes:
  replay     (default) re-run every level's stored proofs; fails if any no
             longer wins. Fast; used by CI.
  stability  each castle must stand untouched when shots miss.
  search     find the fewest-shot solutions and par for every level.
             With --write, par and proofs are merged into the level files.
Levels run in parallel, one Godot process each (--jobs, default: CPU count).
Reports: build/validator/<level>.json
EOF
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	--mode)
		MODE="$2"
		shift
		;;
	--jobs)
		JOBS="$2"
		shift
		;;
	--only)
		ONLY="$2"
		shift
		;;
	--write) WRITE=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done
case "${MODE}" in replay | stability | search) ;; *) die "unknown mode '${MODE}' (see --help)" ;; esac

godot="$(resolve_godot)"
run mkdir -p "${OUT}"
if [[ -n "${ONLY}" ]]; then
	mapfile -t ids < <(tr ',' '\n' <<<"${ONLY}")
else
	mapfile -t ids < <(cd "${SF_GAME_DIR}/data/realms" && python3 -I -c '
import json, glob
realms = sorted((json.load(open(f)) for f in glob.glob("*.json")), key=lambda r: r["order"])
print("\n".join(l for r in realms for l in r["levels"]))')
fi
log "validator: ${MODE} on ${#ids[@]} level(s), ${JOBS} at a time"
if [[ "${DRY_RUN}" == 1 ]]; then
	run printf '%s\n' "${ids[@]}"
	exit 0
fi

one() {
	local id="$1"
	"${godot}" --headless --fixed-fps 60 --path "${SF_GAME_DIR}" res://tools/validator/validator.tscn -- \
		"--validate=${id}" "--mode=${MODE}" "--out=${OUT}/${id}.json" --no-save --no-slowmo 2>&1 |
		grep -E '^\[validator\] [a-z]' || true
}
export -f one
export godot MODE OUT SF_GAME_DIR

# Clear only this run's reports (guarded: never expands to /).
for id in "${ids[@]}"; do
	rm -f "${OUT:?}/${id}.json"
done
printf '%s\n' "${ids[@]}" | xargs -P "${JOBS}" -I{} bash -c 'one "$@"' _ {}

fails=0
reports=()
for id in "${ids[@]}"; do
	if [[ -f "${OUT}/${id}.json" ]] && grep -q '"ok": true' "${OUT}/${id}.json"; then
		reports+=("${OUT}/${id}.json")
	else
		err "${id}: failed (see ${OUT#"${SF_ROOT}"/}/${id}.json)"
		fails=$((fails + 1))
	fi
done
if [[ "${MODE}" == search && "${WRITE}" == 1 && ${#reports[@]} -gt 0 ]]; then
	python3 -I "${SF_ROOT}/tools/levels/apply_report.py" "${SF_GAME_DIR}" "${reports[@]}"
fi
[[ "${fails}" == 0 ]] || die "${fails} level(s) failed ${MODE}"
ok "all ${#ids[@]} level(s) passed ${MODE}"
