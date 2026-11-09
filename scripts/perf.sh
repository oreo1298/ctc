#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# CPU and physics timings of the heaviest moments in the game: the realm
# finales played with their stored winning shots, and every material
# shattering at once. Headless, so the numbers are simulation and script
# cost (what limits slow CPUs); rendering is not measured here.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

usage() {
	cat <<EOF
Usage: scripts/perf.sh [--level ID]... [--budget MS] [--write] [--dry-run]

Plays each level headlessly at a fixed 60 Hz with its stored solution and
prints the cost of a physics tick (percentiles) and the most bodies awake
at once. Default: the three realm finales and a shatter-everything scene.
  --level ID   measure this level instead (repeatable)
  --budget MS  fail if any run's tick p95 is above MS milliseconds
  --write      also write the table to docs/benchmarks/perf.md
  -n, --dry-run  print the commands
  -h, --help   this text
EOF
}

LEVELS=()
BUDGET=""
WRITE=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--level)
		[[ $# -ge 2 ]] || die "--level needs an id"
		LEVELS+=("$2")
		shift
		;;
	--budget)
		[[ $# -ge 2 ]] || die "--budget needs milliseconds"
		BUDGET="$2"
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
[[ ${#LEVELS[@]} -gt 0 ]] || LEVELS=(greenmantle-12 saffron-12 frostfang-12 shatter)
godot="$(resolve_godot)"
need_cmd python3

rows=()
over=()
for id in "${LEVELS[@]}"; do
	if [[ "${id}" == shatter ]]; then
		args=(--level=dev-materials --camera=castle --debug-damage=1.0 --quit-after=6)
		label="every material shattering at once (dev-materials)"
	else
		file="$(find "${SF_GAME_DIR}/data/levels" -name "${id}.json" -print -quit)"
		[[ -n "${file}" ]] || die "no level '${id}'"
		shots="$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(",".join("%s:%s@%s" % (s["ammo"], s["phase"], s["tap"]) for s in d.get("solution", [])))
' "${file}")"
		[[ -n "${shots}" ]] || die "${id} has no stored solution"
		n="$(tr -cd ',' <<<"${shots}" | wc -c)"
		args=(--level="${id}" --unlock-all --no-intro --autoplay="${shots}" --quit-after=$((8 + 7 * (n + 1))))
		label="${id} (${shots})"
	fi
	log "${label}"
	if [[ "${DRY_RUN}" == 1 ]]; then
		run "${godot}" --headless --fixed-fps 60 --path "${SF_GAME_DIR}" -- --no-save --perf "${args[@]}"
		continue
	fi
	out="$("${godot}" --headless --fixed-fps 60 --path "${SF_GAME_DIR}" -- --no-save --perf "${args[@]}" 2>&1 || true)"
	line="$(grep '^\[perf\]' <<<"${out}" | tail -1)"
	[[ -n "${line}" ]] || {
		tail -n 20 <<<"${out}" >&2
		die "no timings from ${id}"
	}
	printf '%s\n' "${line}"
	field() { sed -nE "s/.*[ ]$1=([0-9.]+).*/\\1/p" <<<"${line}"; }
	p50="$(field p50)" p95="$(field p95)" p99="$(field p99)"
	tmax="$(sed -nE 's/.*tick_ms .* max=([0-9.]+) frame_ms.*/\1/p' <<<"${line}")"
	bodies="$(field bodies_max)"
	rows+=("| ${id} | ${p50} | ${p95} | ${p99} | ${tmax} | ${bodies} |")
	if [[ -n "${BUDGET}" ]] && awk -v a="${p95}" -v b="${BUDGET}" 'BEGIN { exit !(a > b) }'; then
		over+=("${id} (tick p95 ${p95} ms > ${BUDGET} ms)")
	fi
done
[[ "${DRY_RUN}" == 1 ]] && exit 0

table="| Scene | tick p50 (ms) | tick p95 | tick p99 | worst tick | most bodies awake |
|---|---|---|---|---|---|
$(printf '%s\n' "${rows[@]}")"
printf '\n%s\n' "${table}"
if [[ "${WRITE}" == 1 ]]; then
	cpu="$(sed -n 's/^model name\s*: //p' /proc/cpuinfo 2>/dev/null | head -1)"
	{
		printf '<!--\nSPDX-FileCopyrightText: 2026 Siegefall contributors\nSPDX-License-Identifier: CC-BY-SA-4.0\n-->\n\n'
		printf '# Performance: the heaviest moments\n\n'
		# shellcheck disable=SC2016 # literal backticks: Markdown code
		printf 'Measured with `scripts/perf.sh` (headless, fixed 60 Hz, Godot %s,\n' "${GODOT_TAG}"
		printf 'godot-rapier %s, one solver thread) on: %s.\n\n' "${RAPIER_VERSION}" "${cpu:-unknown CPU}"
		printf 'A tick is one 1/60 s step: Rapier plus every game script, without\n'
		printf 'drawing. At 60 Hz a frame has 16.7 ms for ticks and rendering together.\n\n%s\n' "${table}"
	} >"${SF_ROOT}/docs/benchmarks/perf.md"
	ok "wrote docs/benchmarks/perf.md"
fi
if [[ ${#over[@]} -gt 0 ]]; then
	die "over budget: ${over[*]}"
fi
