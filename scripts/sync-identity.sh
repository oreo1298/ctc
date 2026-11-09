#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Propagate the identity in app.env (name, slug, version, summary) into every
# file that has to spell it out, or --check that they agree (used by CI).
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity

CHECK=0
usage() {
	cat <<EOF
Usage: scripts/sync-identity.sh [--check] [--dry-run]

Copies APP_NAME / APP_SLUG / APP_VERSION / APP_SUMMARY from app.env into
game/project.godot. Packaging files are generated from templates at build
time (scripts/package.sh), so they cannot drift.
  --check        exit 1 if a file disagrees with app.env; change nothing
  -n, --dry-run  show which files would change
  -h, --help     this text
EOF
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	--check) CHECK=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option '$1' (see --help)" ;;
	esac
	shift
done

# Escape a value for a sed replacement inside a Godot "string".
esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g' -e 's/"/\\\\"/g'; }

# [application] keys to enforce in project.godot.
declare -A godot_keys=(
	['config/name']="\"$(esc "${APP_NAME}")\""
	['config/description']="\"$(esc "${APP_SUMMARY}")\""
	['config/version']="\"$(esc "${APP_VERSION}")\""
	['config/custom_user_dir_name']="\"$(esc "${APP_SLUG}")\""
)

drift=0
sync_file() {
	local file="$1" rel tmp k
	rel="${file#"${SF_ROOT}"/}"
	tmp="$(mktemp)"
	cp "${file}" "${tmp}"
	for k in "${!godot_keys[@]}"; do
		grep -q "^${k}=" "${tmp}" || die "${rel} has no '${k}=' line"
		sed -i "s|^${k}=.*|${k}=${godot_keys[${k}]}|" "${tmp}"
	done
	if cmp -s "${file}" "${tmp}"; then
		ok "${rel} in sync"
	elif [[ "${CHECK}" == 1 ]]; then
		err "${rel} disagrees with app.env:"
		diff -u "${file}" "${tmp}" >&2 || true
		drift=1
	elif [[ "${DRY_RUN}" == 1 ]]; then
		log "would update ${rel}"
	else
		cp "${tmp}" "${file}"
		ok "updated ${rel}"
	fi
	rm -f "${tmp}"
}

sync_file "${SF_GAME_DIR}/project.godot"
[[ "${drift}" == 0 ]] || die "identity drift detected; run 'make sync-identity' and commit."
