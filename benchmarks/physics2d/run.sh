#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Run the 2D physics benchmark against Godot Physics 2D and godot-rapier 2D
# and write a Markdown summary. See benchmarks/physics2d/README.md.
set -Eeuo pipefail
# shellcheck source=../../scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/common.sh"
load_identity

BENCH_DIR="${SF_ROOT}/benchmarks/physics2d"
OUT_DIR="${SF_ROOT}/build/bench/physics2d"
RUNS=2
SCENARIOS=(tower pyramid castle collapse)
# "GodotPhysics2D-tuned" = Godot Physics with 4x solver iterations and softer
# contact bias, to give the built-in engine its best shot.
ENGINES=(GodotPhysics2D GodotPhysics2D-tuned Rapier2D)

usage() {
	cat <<EOF
Usage: benchmarks/physics2d/run.sh [--runs N] [--dry-run]

Fetches the pinned godot-rapier 2D release (SHA-256 checked), then runs each
scenario (${SCENARIOS[*]}) N times (default ${RUNS}) on each engine
(${ENGINES[*]}) headlessly at a fixed 60 Hz tick. Reports go to
build/bench/physics2d/; a summary table is printed and written to
build/bench/physics2d/summary.md.
EOF
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	--runs)
		[[ $# -ge 2 ]] || die "--runs needs a number"
		RUNS="$2"
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

main() {
	local godot
	godot="$(resolve_godot)"
	install_rapier_addon "${BENCH_DIR}/addons"
	run mkdir -p "${OUT_DIR}"
	run "${godot}" --headless --path "${BENCH_DIR}" --import >/dev/null 2>&1 || true
	local engine scenario i
	for engine in "${ENGINES[@]}"; do
		if [[ "${DRY_RUN}" == 0 ]]; then
			{
				printf '[physics]\n2d/physics_engine="%s"\n' "${engine%-tuned}"
				if [[ "${engine}" == *-tuned ]]; then
					printf '2d/solver/solver_iterations=64\n2d/solver/default_contact_bias=0.4\n'
					printf '2d/solver/contact_max_allowed_penetration=0.1\n'
				fi
			} >"${BENCH_DIR}/override.cfg"
		fi
		for scenario in "${SCENARIOS[@]}"; do
			for ((i = 1; i <= RUNS; i++)); do
				log "${engine} ${scenario} run ${i}/${RUNS}"
				run "${godot}" --headless --fixed-fps 60 --path "${BENCH_DIR}" -- \
					"--scenario=${scenario}" "--ticks=900" \
					"--engine-label=${engine}" "--out=${OUT_DIR}/${engine}-${scenario}-${i}.json" >/dev/null
			done
		done
	done
	run rm -f "${BENCH_DIR}/override.cfg"
	run "${SF_ROOT}/.venv/bin/python" -I "${BENCH_DIR}/summarize.py" "${OUT_DIR}"
}

main
