#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# The simulation must be reproducible (validator proofs depend on it) and
# slow motion must be cosmetic: level 1's gold shot played twice without and
# once with slow motion has to end in exactly the same physics state.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run() {
	"${root}/scripts/godot.sh" --headless --fixed-fps 60 --path "${root}/game" -- \
		--level=greenmantle-01 --autoplay=0.65 --quit-after=20 --no-save "$@" 2>&1 |
		sed -n 's/.*\[level\] won .* state=\([0-9a-f]*\).*/\1/p'
}
first="$(run --no-slowmo)"
second="$(run --no-slowmo)"
with="$(run)"
echo "run 1:           ${first:-<no win>}"
echo "run 2:           ${second:-<no win>}"
echo "with slow-mo:    ${with:-<no win>}"
[[ -n "${first}" && "${first}" == "${second}" ]] || {
	echo "FAIL: two identical runs diverged (non-deterministic simulation)" >&2
	exit 1
}
[[ "${with}" == "${first}" ]] || {
	echo "FAIL: slow motion changed the simulation" >&2
	exit 1
}
echo "ok: identical"
