#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Checks that scripts/bootstrap.sh maps every os-release fixture in
# tests/os-release/ to the expected package-manager family.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures="${root}/tests/os-release"
fail=0
while read -r name expected; do
	[[ -z "${name}" || "${name}" == \#* ]] && continue
	got="$("${root}/scripts/bootstrap.sh" --os-release "${fixtures}/${name}" --print-deps 2>/dev/null |
		sed -n 's/^family: *//p')"
	if [[ "${got}" == "${expected}" ]]; then
		printf 'ok   %-22s -> %s\n' "${name}" "${got}"
	else
		printf 'FAIL %-22s -> %s (expected %s)\n' "${name}" "${got}" "${expected}"
		fail=1
	fi
done <"${fixtures}/expected.txt"
exit "${fail}"
