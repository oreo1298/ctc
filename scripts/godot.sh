#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Run the pinned Godot editor binary with the given arguments.
# Honour $GODOT to use a different binary (e.g. a distro package).
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

case "${1:-}" in
-h | --help)
	cat <<EOF
Usage: scripts/godot.sh [--dry-run] [godot arguments...]

Runs the pinned Godot ${GODOT_TAG} (installed by scripts/bootstrap.sh) with the
given arguments. Set GODOT=/path/to/godot to override the binary.
  --dry-run   print the command instead of running it (must come first)
Examples:
  scripts/godot.sh --path game              # run the game
  scripts/godot.sh --path game --editor     # open the editor
  scripts/godot.sh --headless --path game -- --smoke-test
EOF
	exit 0
	;;
--dry-run)
	DRY_RUN=1
	shift
	;;
esac

bin="$(resolve_godot)"
if [[ "${DRY_RUN}" == 1 ]]; then
	run "${bin}" "$@"
	exit 0
fi
exec "${bin}" "$@"
