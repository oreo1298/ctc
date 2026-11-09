#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Dry-runs the whole bootstrap for every package-manager family, with and
# without --yes, and checks it exits 0 and prints the right install command.
# (Regression test: an interactive run used to die silently under set -e.)
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures="${root}/tests/os-release"
fail=0
declare -A expect=(
	[cachyos]="pacman -S --needed" [arch]="pacman -S --needed" [ubuntu]="apt-get install"
	[debian]="apt-get install" [fedora]="dnf install" [nobara]="dnf install"
	[opensuse-tumbleweed]="zypper" [opensuse-leap]="zypper" [void]="xbps-install"
	[gentoo]="emerge --noreplace" [silverblue]="image-based" [steamos]="image-based"
	[unknown]="Unrecognised distribution"
)
for name in "${!expect[@]}"; do
	for yes in "" "--yes"; do
		out="$("${root}/scripts/bootstrap.sh" --dry-run --os-release "${fixtures}/${name}" \
			--editor-only ${yes:+"${yes}"} 2>&1)" && code=0 || code=$?
		if [[ "${code}" != 0 ]]; then
			printf 'FAIL %-20s %-5s exit %s\n%s\n' "${name}" "${yes:-}" "${code}" "${out}"
			fail=1
		elif [[ "${out}" != *"${expect[${name}]}"* ]]; then
			printf 'FAIL %-20s %-5s missing "%s"\n%s\n' "${name}" "${yes:-}" "${expect[${name}]}" "${out}"
			fail=1
		else
			printf 'ok   %-20s %-5s\n' "${name}" "${yes:-}"
		fi
	done
done
exit "${fail}"
