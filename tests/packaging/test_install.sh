#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# install.sh / uninstall.sh in a throw-away HOME: fresh install, re-install
# (upgrade), launcher and files, smoke test, uninstall, purge, and that the
# portable tarball works the same way. Needs `make build` (and `make package`
# for the tarball part, which is skipped otherwise). No root, no network.
set -Eeuo pipefail
# shellcheck source=../../scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/common.sh"
load_identity

case "${1:-}" in
-h | --help)
	echo "Usage: tests/packaging/test_install.sh   (needs 'make build'; uses dist/ if present)"
	exit 0
	;;
esac

arch="$(host_arch)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fail() {
	err "$*"
	exit 1
}

check_install() {
	local home="$1" p="$1/.local"
	[[ -x "${p}/bin/${APP_SLUG}" ]] || fail "no ${p}/bin/${APP_SLUG}"
	[[ -f "${p}/share/applications/${APP_ID}.desktop" ]] || fail "no desktop file"
	grep -q "^Exec=${p}/bin/${APP_SLUG}$" "${p}/share/applications/${APP_ID}.desktop" ||
		fail "launcher does not point at the installed binary"
	[[ -f "${p}/share/icons/hicolor/256x256/apps/${APP_ID}.png" ]] || fail "no icon"
	[[ -f "${p}/share/man/man6/${APP_SLUG}.6.gz" ]] || fail "no man page"
	[[ -x "${p}/lib/${APP_SLUG}/uninstall.sh" ]] || fail "no uninstaller next to the game"
	local out
	out="$(HOME="${home}" XDG_DATA_HOME="" XDG_CONFIG_HOME="" timeout 120 \
		"${p}/bin/${APP_SLUG}" --headless -- --smoke-test 2>&1)" || fail "game did not start: ${out}"
	grep -q '^\[smoke\] ok' <<<"${out}" || fail "smoke test failed: ${out}"
	[[ -d "${home}/.local/share/${APP_SLUG}" ]] || fail "the game wrote no user data"
}

check_gone() {
	local p="$1/.local"
	[[ ! -e "${p}/lib/${APP_SLUG}" ]] || fail "left behind: ${p}/lib/${APP_SLUG}"
	[[ ! -e "${p}/bin/${APP_SLUG}" ]] || fail "left behind: ${p}/bin/${APP_SLUG}"
	[[ ! -e "${p}/share/applications/${APP_ID}.desktop" ]] || fail "left behind: desktop file"
	[[ ! -e "${p}/share/man/man6/${APP_SLUG}.6.gz" ]] || fail "left behind: man page"
}

# ------------------------------------------------------- from the repository
home="${work}/home-repo"
mkdir -p "${home}"
log "install from the repository build"
HOME="${home}" "${SF_ROOT}/scripts/install.sh" >/dev/null 2>&1 || fail "install.sh failed"
HOME="${home}" "${SF_ROOT}/scripts/install.sh" >/dev/null 2>&1 || fail "re-running install.sh failed"
check_install "${home}"
ok "install, re-install, launch"
HOME="${home}" "${home}/.local/lib/${APP_SLUG}/uninstall.sh" >/dev/null 2>&1 || fail "uninstall failed"
check_gone "${home}"
[[ -d "${home}/.local/share/${APP_SLUG}" ]] || fail "uninstall without --purge removed player data"
HOME="${home}" "${SF_ROOT}/scripts/uninstall.sh" >/dev/null 2>&1 || fail "second uninstall should be a no-op"
if HOME="${home}" "${SF_ROOT}/scripts/uninstall.sh" --purge </dev/null >/dev/null 2>&1; then
	fail "--purge without a terminal or --yes must refuse"
fi
HOME="${home}" "${SF_ROOT}/scripts/uninstall.sh" --purge --yes >/dev/null 2>&1 || fail "purge failed"
[[ ! -e "${home}/.local/share/${APP_SLUG}" ]] || fail "--purge kept player data"
ok "uninstall keeps saves; --purge removes them; both are safe to repeat"

# ------------------------------------------------------- from the tarball
tarball="${SF_ROOT}/dist/${APP_SLUG}-${APP_VERSION}-linux-${arch}.tar.gz"
if [[ -f "${tarball}" ]]; then
	home="${work}/home-tar"
	mkdir -p "${home}"
	tar -xzf "${tarball}" -C "${work}"
	dir="${work}/${APP_SLUG}-${APP_VERSION}-linux-${arch}"
	log "install from $(basename "${tarball}")"
	HOME="${home}" "${dir}/install.sh" >/dev/null 2>&1 || fail "tarball install.sh failed"
	check_install "${home}"
	rm -rf "${dir}"
	HOME="${home}" "${home}/.local/lib/${APP_SLUG}/uninstall.sh" --purge --yes >/dev/null 2>&1 ||
		fail "uninstall after deleting the tarball failed"
	check_gone "${home}"
	ok "tarball install; uninstall works after the tarball is gone"
else
	warn "no ${tarball#"${SF_ROOT}"/}; skipping the tarball check (run 'make package')"
fi
ok "install/uninstall tests passed"
