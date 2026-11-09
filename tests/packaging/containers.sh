#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Install, run and remove the packages in dist/ inside clean containers of
# several distributions. Used by CI and runnable locally with docker or
# podman. Needs `make build && make package` first.
set -Eeuo pipefail
# shellcheck source=../../scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/common.sh"
load_identity

ALL=(arch ubuntu debian fedora tumbleweed void)

usage() {
	cat <<EOF
Usage: tests/packaging/containers.sh [--distro NAME]... [options]

For each distribution: install ${APP_NAME} the native way, run the headless
smoke test, check the menu entry and icon, then uninstall and check nothing
is left behind.
  arch        makepkg the ${APP_SLUG}-bin PKGBUILD (local tarball), pacman -U
  ubuntu      apt install ./${APP_SLUG}_*.deb          (ubuntu:24.04)
  debian      apt install ./${APP_SLUG}_*.deb          (debian:stable-slim)
  fedora      dnf install ./${APP_SLUG}-*.rpm          (fedora:latest)
  tumbleweed  zypper install ./${APP_SLUG}-*.rpm       (opensuse/tumbleweed)
  void        tarball + install.sh/uninstall.sh as a normal user

  --distro NAME   run only this one (repeatable; default: all)
  --engine E      docker or podman (default: whichever is installed)
  --arch A        x86_64 (default) or arm64 (needs an arm64 host)
  --engine-arg A  extra argument for '<engine> run' (repeatable), e.g. a CA
                  bundle mount when a proxy intercepts TLS
  --setup CMD     shell commands run first in every container, e.g. to
                  switch package mirrors to https
  -n, --dry-run   print the commands
  -h, --help      this text
EOF
}

DISTROS=()
ENGINE=""
EXTRA=()
SETUP=":"
ARCH="x86_64"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--distro)
		[[ $# -ge 2 ]] || die "--distro needs a name"
		[[ " ${ALL[*]} " == *" $2 "* ]] || die "unknown distro '$2' (${ALL[*]})"
		DISTROS+=("$2")
		shift
		;;
	--engine)
		[[ $# -ge 2 ]] || die "--engine needs docker or podman"
		ENGINE="$2"
		shift
		;;
	--arch)
		[[ $# -ge 2 ]] || die "--arch needs a value"
		ARCH="$2"
		shift
		;;
	--engine-arg)
		[[ $# -ge 2 ]] || die "--engine-arg needs a value"
		EXTRA+=("$2")
		shift
		;;
	--setup)
		[[ $# -ge 2 ]] || die "--setup needs commands"
		SETUP="$2"
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
[[ ${#DISTROS[@]} -gt 0 ]] || DISTROS=("${ALL[@]}")
if [[ -z "${ENGINE}" ]]; then
	if have_cmd docker; then ENGINE=docker; elif have_cmd podman; then ENGINE=podman; fi
fi
[[ -n "${ENGINE}" ]] || die "needs docker or podman"

DIST="${SF_ROOT}/dist"
case "${ARCH}" in
x86_64) DEB_ARCH=amd64 RPM_ARCH=x86_64 ;;
arm64) DEB_ARCH=arm64 RPM_ARCH=aarch64 ;;
*) die "unknown arch '${ARCH}'" ;;
esac
TARBALL="${APP_SLUG}-${APP_VERSION}-linux-${ARCH}.tar.gz"
DEB="${APP_SLUG}_${APP_VERSION}-1_${DEB_ARCH}.deb"
RPM="${APP_SLUG}-${APP_VERSION}-1.${RPM_ARCH}.rpm"

# Checks shared by every distribution, run inside the container.
read -r -d '' CHECKS <<EOF || true
smoke() {
	out="\$("\$1" --headless -- --smoke-test 2>&1)" || { printf '%s\n' "\${out}"; exit 1; }
	printf '%s\n' "\${out}" | grep -q '^\[smoke\] ok' || { printf '%s\n' "\${out}"; echo 'smoke test failed'; exit 1; }
	echo "smoke ok: \$1"
}
installed() {
	test -f "\$1/share/applications/${APP_ID}.desktop"
	test -f "\$1/share/icons/hicolor/256x256/apps/${APP_ID}.png"
	test -f "\$1/share/metainfo/${APP_ID}.metainfo.xml"
	test -x "\$1/lib/${APP_SLUG}/${APP_SLUG}"
	echo "files ok: \$1"
}
gone() {
	test ! -e "\$1/lib/${APP_SLUG}" || { echo "left behind: \$1/lib/${APP_SLUG}"; ls -la "\$1/lib/${APP_SLUG}"; exit 1; }
	test ! -e "\$1/bin/${APP_SLUG}" || { echo "left behind: \$1/bin/${APP_SLUG}"; exit 1; }
	test ! -e "\$1/share/applications/${APP_ID}.desktop" || { echo "left behind: desktop file"; exit 1; }
	echo "removed ok: \$1"
}
EOF

script_for() {
	case "$1" in
	ubuntu | debian)
		cat <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends /dist/${DEB} >/dev/null
installed /usr
smoke ${APP_SLUG}
smoke /usr/games/${APP_SLUG}
apt-get remove -y -qq ${APP_SLUG} >/dev/null
gone /usr
EOF
		;;
	fedora)
		cat <<EOF
# Weak dependencies (sound servers, Vulkan) are what a desktop already has;
# skipping them keeps the container small.
dnf install -y -q --setopt=install_weak_deps=False /dist/${RPM}
installed /usr
smoke ${APP_SLUG}
dnf remove -y -q ${APP_SLUG}
gone /usr
EOF
		;;
	tumbleweed)
		cat <<EOF
zypper --non-interactive --quiet install --no-recommends --allow-unsigned-rpm /dist/${RPM}
installed /usr
smoke ${APP_SLUG}
zypper --non-interactive --quiet remove ${APP_SLUG}
gone /usr
EOF
		;;
	arch)
		cat <<EOF
pacman -Syu --noconfirm --needed base-devel >/dev/null
useradd -m builder
mkdir /home/builder/pkg
cp /dist/aur/${APP_SLUG}-bin/PKGBUILD /dist/${TARBALL} /home/builder/pkg/
# Build from the local tarball instead of the (not yet published) release.
sed -i 's|^source_x86_64=.*|source_x86_64=("${TARBALL}")|; s|^source_aarch64=.*|source_aarch64=("${TARBALL}")|' /home/builder/pkg/PKGBUILD
chown -R builder /home/builder/pkg
# --nodeps: pacman -U below installs the runtime dependencies from the repos.
su builder -c 'cd ~/pkg && makepkg --printsrcinfo > .SRCINFO && makepkg -f --noconfirm --nodeps' >/dev/null
pacman -U --noconfirm /home/builder/pkg/${APP_SLUG}-bin-*.pkg.tar.zst >/dev/null
installed /usr
smoke ${APP_SLUG}
pacman -R --noconfirm ${APP_SLUG}-bin >/dev/null
gone /usr
EOF
		;;
	void)
		cat <<EOF
xbps-install -Syu xbps >/dev/null
xbps-install -Sy bash tar gzip shadow >/dev/null
useradd -m player
su player -s /bin/bash -c '
set -e
cd ~ && tar xzf /dist/${TARBALL}
cd ${APP_SLUG}-${APP_VERSION}-linux-${ARCH}
./install.sh
./install.sh
'
installed /home/player/.local
smoke /home/player/.local/bin/${APP_SLUG}
# Run once as the player too, so there is player data for --purge to remove.
su player -s /bin/bash -c '~/.local/bin/${APP_SLUG} --headless -- --smoke-test' | grep -q '^\[smoke\] ok'
test -d /home/player/.local/share/${APP_SLUG}
su player -s /bin/bash -c '~/.local/lib/${APP_SLUG}/uninstall.sh --purge --yes'
gone /home/player/.local
test ! -e /home/player/.local/share/${APP_SLUG} || { echo "player data left"; exit 1; }
echo "purge ok"
EOF
		;;
	esac
}

image_for() {
	case "$1" in
	arch) echo "archlinux:latest" ;;
	ubuntu) echo "ubuntu:24.04" ;;
	debian) echo "debian:stable-slim" ;;
	fedora) echo "fedora:latest" ;;
	tumbleweed) echo "opensuse/tumbleweed:latest" ;;
	void) echo "ghcr.io/void-linux/void-glibc-full:latest" ;;
	esac
}

needs_for() {
	case "$1" in
	ubuntu | debian) echo "${DEB}" ;;
	fedora | tumbleweed) echo "${RPM}" ;;
	arch) echo "${TARBALL} aur/${APP_SLUG}-bin/PKGBUILD" ;;
	void) echo "${TARBALL}" ;;
	esac
}

# Behind a proxy? Pass its settings on to the package managers inside.
env_args=()
for v in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
	[[ -n "${!v:-}" ]] && env_args+=(-e "${v}")
done

failed=()
for d in "${DISTROS[@]}"; do
	for f in $(needs_for "${d}"); do
		[[ "${DRY_RUN}" == 1 || -f "${DIST}/${f}" ]] || die "dist/${f} is missing; run 'make build && make package'"
	done
	log "${d}: $(image_for "${d}")"
	if run "${ENGINE}" run --rm --network=host "${env_args[@]}" "${EXTRA[@]}" \
		-v "${DIST}:/dist:ro" "$(image_for "${d}")" \
		sh -euc "${CHECKS}
${SETUP}
$(script_for "${d}")"; then
		ok "${d}"
	else
		err "${d} failed"
		failed+=("${d}")
	fi
done
[[ ${#failed[@]} -eq 0 ]] || die "failed on: ${failed[*]}"
ok "all ${#DISTROS[@]} distribution(s) passed"
