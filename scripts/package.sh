#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Turn the exports in build/export into distributable packages in dist/.
# Every format is generated from app.env and the templates in packaging/.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_identity
# shellcheck source=lib/stage.sh
source "${SF_ROOT}/scripts/lib/stage.sh"

ALL_FORMATS=(tar appimage deb rpm flatpak aur winzip nsis)
FLATPAK_RUNTIME="25.08"

usage() {
	cat <<EOF
Usage: scripts/package.sh [FORMAT]... [options]

Packages the builds in build/export (run 'make build' first) into dist/:
  tar       portable tarball with install.sh/uninstall.sh   (tar, gzip)
  appimage  single-file AppImage                            (mksquashfs)
  deb       Debian/Ubuntu package                           (dpkg-deb)
  rpm       Fedora/openSUSE package                         (rpmbuild)
  flatpak   Flatpak manifest, plus a bundle if possible     (flatpak-builder)
  aur       PKGBUILDs: ${APP_SLUG}-bin and ${APP_SLUG} (from source)
  winzip    portable Windows zip                            (zip)
  nsis      Windows installer                               (makensis)
  all       every format whose tool is installed (default)
Nix: 'nix build' uses flake.nix directly (see docs/PACKAGING.md).

  --arch A        x86_64, arm64 or all (default: every Linux build present)
  --release-url U where release assets will be downloaded from (AUR -bin,
                  Flatpak), default: ${APP_HOMEPAGE}/releases/download/v${APP_VERSION}
  -n, --dry-run   print what would run
  -h, --help      this text
EOF
}

FORMATS=()
ARCHS=()
RELEASE_URL="${APP_HOMEPAGE}/releases/download/v${APP_VERSION}"
while [[ $# -gt 0 ]]; do
	case "$1" in
	tar | appimage | deb | rpm | flatpak | aur | winzip | nsis | all) FORMATS+=("$1") ;;
	--arch)
		[[ $# -ge 2 ]] || die "--arch needs a value"
		case "$2" in
		all) ARCHS=(x86_64 arm64) ;;
		x86_64 | arm64) ARCHS+=("$2") ;;
		*) die "unknown architecture '$2' (x86_64, arm64 or all)" ;;
		esac
		shift
		;;
	--release-url)
		[[ $# -ge 2 ]] || die "--release-url needs a value"
		RELEASE_URL="${2%/}"
		shift
		;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown format or option '$1' (see --help)" ;;
	esac
	shift
done

EXPLICIT=1
if [[ ${#FORMATS[@]} -eq 0 || " ${FORMATS[*]} " == *" all "* ]]; then
	FORMATS=("${ALL_FORMATS[@]}")
	EXPLICIT=0
fi
if [[ ${#ARCHS[@]} -eq 0 ]]; then
	for a in x86_64 arm64; do
		[[ -x "$(export_dir "${a}")/${APP_SLUG}" ]] && ARCHS+=("${a}")
	done
fi

DIST="${SF_ROOT}/dist"
PKG="${SF_BUILD}/pkg"
WIN_SRC="${SF_EXPORT}/windows-x86_64"
STEM="${APP_SLUG}-${APP_VERSION}"
run mkdir -p "${DIST}" "${PKG}"

made=()
skipped=()

# tool_or_skip FORMAT CMD HINT -- true if CMD exists. A missing tool is fatal
# when the format was asked for by name, otherwise it is skipped.
tool_or_skip() {
	if have_cmd "$2"; then
		return 0
	fi
	if [[ "${EXPLICIT}" == 1 ]]; then
		die "$1 needs '$2' (${3})"
	fi
	skipped+=("$1 (needs $2: $3)")
	return 1
}

need_linux_builds() {
	if [[ ${#ARCHS[@]} -eq 0 ]]; then
		[[ "${EXPLICIT}" == 1 ]] && die "no Linux build in build/export; run 'make build' first"
		skipped+=("$1 (no Linux build; run 'make build')")
		return 1
	fi
}

need_windows_build() {
	if [[ ! -f "${WIN_SRC}/${APP_NAME}.exe" ]]; then
		[[ "${EXPLICIT}" == 1 ]] && die "no Windows build; run: make build ARGS='--target windows-x86_64'"
		skipped+=("$1 (no Windows build; run 'make build ARGS=--target=windows-x86_64')")
		return 1
	fi
}

# stage ARCH PREFIX -> fresh staged tree in build/pkg/stage-ARCH-<tag>
stage() {
	local arch="$1" prefix="$2" tag="$3" dir
	dir="${PKG}/stage-${arch}-${tag}"
	run rm -rf "${dir}"
	stage_linux "${arch}" "${dir}" "${prefix}"
	printf '%s' "${dir}"
}

# ------------------------------------------------------------------- tar ---
tarball_of() { printf '%s/%s-linux-%s.tar.gz' "${DIST}" "${STEM}" "$1"; }

make_tar() {
	local arch name root src
	for arch in "${ARCHS[@]}"; do
		name="${STEM}-linux-${arch}"
		root="${PKG}/tar/${name}"
		src="$(export_dir "${arch}")"
		log "tar: ${name}.tar.gz"
		run rm -rf "${PKG}/tar"
		stage_linux "${arch}" "${root}/files" ""
		run install -m 0644 "${src}/BUILD_INFO" "${root}/files/lib/${APP_SLUG}/BUILD_INFO"
		run mkdir -p "${root}/scripts/lib"
		run install -m 0755 "${SF_ROOT}/scripts/install.sh" "${SF_ROOT}/scripts/uninstall.sh" "${root}/scripts/"
		run install -m 0644 "${SF_ROOT}/scripts/lib/common.sh" "${SF_ROOT}/scripts/lib/stage.sh" "${root}/scripts/lib/"
		run install -m 0644 "${SF_ROOT}/app.env" "${SF_ROOT}/toolchain.lock" "${SF_ROOT}/README.md" "${SF_ROOT}/LICENSE" "${root}/"
		if [[ "${DRY_RUN}" == 0 ]]; then
			cat >"${root}/install.sh" <<EOF
#!/usr/bin/env bash
# Install ${APP_NAME} for this user (~/.local). See --help for options.
exec "\$(dirname "\$0")/scripts/install.sh" "\$@"
EOF
			chmod 0755 "${root}/install.sh"
		fi
		run ln -sfn "files/lib/${APP_SLUG}/${APP_SLUG}" "${root}/${APP_SLUG}"
		run tar --sort=name --owner=0 --group=0 --numeric-owner \
			${SOURCE_DATE_EPOCH:+--mtime="@${SOURCE_DATE_EPOCH}"} \
			-C "${PKG}/tar" -czf "$(tarball_of "${arch}")" "${name}"
		made+=("$(tarball_of "${arch}")")
	done
}

# -------------------------------------------------------------- appimage ---
make_appimage() {
	tool_or_skip appimage mksquashfs "install squashfs-tools" || return 0
	local arch appdir rt sum out uname_arch
	for arch in "${ARCHS[@]}"; do
		uname_arch="$(rpm_arch "${arch}")"
		out="${DIST}/${APP_NAME}-${APP_VERSION}-${uname_arch}.AppImage"
		log "appimage: $(basename "${out}")"
		if [[ "${arch}" == x86_64 ]]; then
			sum="${APPIMAGE_RUNTIME_SHA256_X86_64}"
		else
			sum="${APPIMAGE_RUNTIME_SHA256_ARM64}"
		fi
		rt="$(sf_cache_dir)/appimage/runtime-${APPIMAGE_RUNTIME_VERSION}-${uname_arch}"
		fetch_pinned "${APPIMAGE_RUNTIME_URL}/runtime-${uname_arch}" "${rt}" "${sum}"
		appdir="${PKG}/appimage/${APP_NAME}.AppDir"
		run rm -rf "${PKG}/appimage"
		stage_linux "${arch}" "${appdir}" "/usr"
		run ln -sfn "usr/lib/${APP_SLUG}/${APP_SLUG}" "${appdir}/AppRun"
		run cp "${appdir}/usr/share/applications/${APP_ID}.desktop" "${appdir}/${APP_ID}.desktop"
		run cp "${SF_BUILD}/icons/256.png" "${appdir}/${APP_ID}.png"
		run ln -sfn "${APP_ID}.png" "${appdir}/.DirIcon"
		run mksquashfs "${appdir}" "${PKG}/appimage/payload.squashfs" -root-owned -noappend \
			-comp zstd -quiet -no-progress ${SOURCE_DATE_EPOCH:+-mkfs-time "${SOURCE_DATE_EPOCH}" -all-time "${SOURCE_DATE_EPOCH}"}
		if [[ "${DRY_RUN}" == 0 ]]; then
			cat "${rt}" "${PKG}/appimage/payload.squashfs" >"${out}"
			chmod 0755 "${out}"
		fi
		made+=("${out}")
	done
}

# ------------------------------------------------------------------- deb ---
make_deb() {
	tool_or_skip deb dpkg-deb "install dpkg (dpkg-deb)" || return 0
	local arch root size out darch
	for arch in "${ARCHS[@]}"; do
		darch="$(deb_arch "${arch}")"
		out="${DIST}/${APP_SLUG}_$(version_tilde)-1_${darch}.deb"
		log "deb: $(basename "${out}")"
		root="$(stage "${arch}" /usr deb)"
		render_template "${SF_PACKAGING}/deb/copyright.in" "${root}/usr/share/doc/${APP_SLUG}/copyright"
		render_template "${SF_PACKAGING}/deb/lintian-overrides.in" \
			"${root}/usr/share/lintian/overrides/${APP_SLUG}"
		# Debian keeps games in /usr/games (on PATH on Debian and Ubuntu).
		run mkdir -p "${root}/usr/games"
		run ln -sfn "../lib/${APP_SLUG}/${APP_SLUG}" "${root}/usr/games/${APP_SLUG}"
		if [[ "${DRY_RUN}" == 0 ]]; then
			printf '%s (%s-1) unstable; urgency=low\n\n  * Release %s.\n\n -- %s <%s>  %s\n' \
				"${APP_SLUG}" "$(version_tilde)" "${APP_VERSION}" "${APP_DEVELOPER}" "${APP_CONTACT}" \
				"$(date -u -d "$(release_date)" -R)" | gzip -9n >"${root}/usr/share/doc/${APP_SLUG}/changelog.Debian.gz"
			size="$(du -sk --apparent-size "${root}" | cut -f1)"
		else
			size=0
		fi
		run mkdir -p "${root}/DEBIAN"
		render_template "${SF_PACKAGING}/deb/control.in" "${root}/DEBIAN/control" \
			"DEB_ARCH=${darch}" "INSTALLED_SIZE=${size}"
		run dpkg-deb --root-owner-group -Zxz --build "${root}" "${out}"
		made+=("${out}")
	done
}

# ------------------------------------------------------------------- rpm ---
make_rpm() {
	tool_or_skip rpm rpmbuild "install rpm-build (Fedora) or rpm (Debian/Ubuntu)" || return 0
	local arch root top rarch spec
	for arch in "${ARCHS[@]}"; do
		rarch="$(rpm_arch "${arch}")"
		log "rpm: ${APP_SLUG}-$(version_tilde)-1.${rarch}.rpm"
		root="$(stage "${arch}" /usr rpm)"
		top="${PKG}/rpmbuild"
		spec="${top}/SPECS/${APP_SLUG}.spec"
		run rm -rf "${top}"
		run mkdir -p "${top}/SPECS" "${top}/RPMS"
		render_template "${SF_PACKAGING}/rpm/app.spec.in" "${spec}" \
			"RPM_DATE=$(LC_ALL=C date -u -d "$(release_date)" '+%a %b %d %Y')"
		run rpmbuild --quiet -bb --target "${rarch}" \
			--define "_topdir ${top}" --define "sf_stage ${root}" "${spec}"
		run cp "${top}/RPMS/${rarch}/${APP_SLUG}-$(version_tilde)-1.${rarch}.rpm" "${DIST}/"
		made+=("${DIST}/${APP_SLUG}-$(version_tilde)-1.${rarch}.rpm")
	done
}

# --------------------------------------------------------------- flatpak ---
make_flatpak() {
	local arch fa sources="" manifest dir tarball sum
	dir="${PKG}/flatpak"
	manifest="${dir}/${APP_ID}.yml"
	run mkdir -p "${dir}"
	for arch in "${ARCHS[@]}"; do
		tarball="$(tarball_of "${arch}")"
		[[ "${DRY_RUN}" == 1 || -f "${tarball}" ]] || make_tar_for "${arch}"
		fa="$(rpm_arch "${arch}")"
		sum=0
		[[ "${DRY_RUN}" == 1 ]] || sum="$(sha256_of "${tarball}")"
		sources+="      - type: archive
        only-arches: [${fa}]
        @WHERE_${arch}@
        sha256: ${sum}
"
	done
	sources="${sources%$'\n'}"
	local local_src="${sources}" dist_src="${sources}"
	for arch in "${ARCHS[@]}"; do
		local_src="${local_src//@WHERE_${arch}@/path: $(tarball_of "${arch}")}"
		dist_src="${dist_src//@WHERE_${arch}@/url: ${RELEASE_URL}/${STEM}-linux-${arch}.tar.gz}"
	done
	# A local manifest to build from dist/, and one with release URLs to publish.
	render_template "${SF_PACKAGING}/flatpak/manifest.yml.in" "${manifest}" \
		"FLATPAK_RUNTIME=${FLATPAK_RUNTIME}" "FLATPAK_SOURCES=${local_src}"
	render_template "${SF_PACKAGING}/flatpak/manifest.yml.in" "${DIST}/${APP_ID}.yml" \
		"FLATPAK_RUNTIME=${FLATPAK_RUNTIME}" "FLATPAK_SOURCES=${dist_src}"
	made+=("${DIST}/${APP_ID}.yml")
	if ! have_cmd flatpak-builder; then
		skipped+=("flatpak bundle (needs flatpak-builder; the manifest was written)")
		return 0
	fi
	# The runtime comes from Flathub; never add remotes behind the user's back.
	if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
		local hint="flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
		[[ "${EXPLICIT}" == 1 ]] && die "the Flatpak bundle needs the Flathub remote for its runtime. Add it with: ${hint}"
		skipped+=("flatpak bundle (no Flathub remote; the manifest was written. Add it with: ${hint})")
		return 0
	fi
	log "flatpak: building ${APP_ID} (runtime ${FLATPAK_RUNTIME})"
	run flatpak-builder --user --force-clean --install-deps-from=flathub --disable-rofiles-fuse \
		--repo="${dir}/repo" "${dir}/build" "${manifest}"
	run flatpak build-bundle "${dir}/repo" "${DIST}/${APP_NAME}-${APP_VERSION}.flatpak" "${APP_ID}"
	made+=("${DIST}/${APP_NAME}-${APP_VERSION}.flatpak")
}

make_tar_for() {
	local saved=("${ARCHS[@]}")
	ARCHS=("$1")
	make_tar
	ARCHS=("${saved[@]}")
}

# ------------------------------------------------------------------- aur ---
make_aur() {
	local dir="${DIST}/aur" x86="" arm="" sx="" sa=""
	for arch in "${ARCHS[@]}"; do
		[[ "${DRY_RUN}" == 1 || -f "$(tarball_of "${arch}")" ]] || make_tar_for "${arch}"
	done
	if [[ -f "$(tarball_of x86_64)" ]]; then
		x86="${RELEASE_URL}/${STEM}-linux-x86_64.tar.gz"
		sx="$(sha256_of "$(tarball_of x86_64)")"
	fi
	if [[ -f "$(tarball_of arm64)" ]]; then
		arm="${RELEASE_URL}/${STEM}-linux-arm64.tar.gz"
		sa="$(sha256_of "$(tarball_of arm64)")"
	fi
	log "aur: ${APP_SLUG}-bin and ${APP_SLUG} PKGBUILDs"
	run mkdir -p "${dir}/${APP_SLUG}-bin" "${dir}/${APP_SLUG}"
	render_template "${SF_PACKAGING}/aur/PKGBUILD-bin.in" "${dir}/${APP_SLUG}-bin/PKGBUILD" \
		"SOURCE_X86_64=${x86}" "SHA256_X86_64=${sx:-SKIP}" \
		"SOURCE_ARM64=${arm}" "SHA256_ARM64=${sa:-SKIP}"
	if [[ "${DRY_RUN}" == 0 ]]; then
		# Drop an architecture whose tarball was not built rather than ship SKIP.
		[[ -n "${x86}" ]] || sed -i -e "/_x86_64=/d" -e "s/'x86_64' //" "${dir}/${APP_SLUG}-bin/PKGBUILD"
		[[ -n "${arm}" ]] || sed -i -e "/_aarch64=/d" -e "s/ 'aarch64'//" "${dir}/${APP_SLUG}-bin/PKGBUILD"
	fi
	render_template "${SF_PACKAGING}/aur/PKGBUILD.in" "${dir}/${APP_SLUG}/PKGBUILD" \
		"SOURCE_GIT=git+${APP_HOMEPAGE}.git#tag=v\${_ver}" \
		"GODOT_RELEASE_URL=${GODOT_RELEASE_URL}" "GODOT_SHA512_TEMPLATES=${GODOT_SHA512_TEMPLATES}" \
		"GODOT_SHA512_LINUX_X86_64=${GODOT_SHA512_LINUX_X86_64}" \
		"GODOT_SHA512_LINUX_ARM64=${GODOT_SHA512_LINUX_ARM64}" \
		"RAPIER_VERSION=${RAPIER_VERSION}" "RAPIER_URL=${RAPIER_URL}" "RAPIER_SHA256=${RAPIER_SHA256}"
	local p
	for p in "${APP_SLUG}-bin" "${APP_SLUG}"; do
		if have_cmd makepkg; then
			(cd "${dir}/${p}" && run makepkg --printsrcinfo >.SRCINFO)
		fi
	done
	have_cmd makepkg || skipped+=(".SRCINFO (needs makepkg; run 'makepkg --printsrcinfo > .SRCINFO' on Arch before pushing to the AUR)")
	made+=("${dir}/${APP_SLUG}-bin/PKGBUILD" "${dir}/${APP_SLUG}/PKGBUILD")
}

# --------------------------------------------------------------- windows ---
stage_windows() {
	local root="$1"
	run rm -rf "${root}"
	run mkdir -p "${root}"
	run cp "${WIN_SRC}/${APP_NAME}.exe" "${WIN_SRC}"/*.dll "${WIN_SRC}/THIRD-PARTY-NOTICES.txt" "${root}/"
	render_template "${SF_PACKAGING}/windows/README.txt.in" "${root}/README.txt"
	if [[ "${DRY_RUN}" == 0 ]]; then
		sed -i 's/$/\r/' "${root}/README.txt"
		sed 's/$/\r/' "${SF_ROOT}/LICENSE" >"${root}/LICENSE.txt"
	fi
}

make_winzip() {
	need_windows_build winzip || return 0
	tool_or_skip winzip zip "install zip" || return 0
	local out="${DIST}/${STEM}-windows-x86_64.zip"
	log "winzip: $(basename "${out}")"
	stage_windows "${PKG}/winzip/${APP_NAME}"
	run rm -f "${out}"
	(cd "${PKG}/winzip" && run zip -q -r -X "${out}" "${APP_NAME}")
	made+=("${out}")
}

make_nsis() {
	need_windows_build nsis || return 0
	tool_or_skip nsis makensis "install nsis" || return 0
	local out="${DIST}/${STEM}-windows-x86_64-setup.exe" src="${PKG}/nsis/${APP_NAME}"
	log "nsis: $(basename "${out}")"
	stage_windows "${src}"
	run makensis -V2 -INPUTCHARSET UTF8 \
		"-DAPP_NAME=${APP_NAME}" "-DAPP_ID=${APP_ID}" "-DAPP_SLUG=${APP_SLUG}" \
		"-DAPP_VERSION=${APP_VERSION}" "-DAPP_VERSION_NUM=$(version_numeric)" \
		"-DAPP_DEVELOPER=${APP_DEVELOPER}" \
		"-DAPP_HOMEPAGE=${APP_HOMEPAGE}" "-DSRC_DIR=${src}" "-DOUT_FILE=${out}" \
		"-DICON=${SF_BUILD}/icons/${APP_SLUG}.ico" "-DLICENSE_FILE=${src}/LICENSE.txt" \
		"${SF_PACKAGING}/windows/installer.nsi"
	made+=("${out}")
}

# ------------------------------------------------------------------ main ---
for f in "${FORMATS[@]}"; do
	case "${f}" in
	tar) need_linux_builds tar && make_tar ;;
	appimage) need_linux_builds appimage && make_appimage ;;
	deb) need_linux_builds deb && make_deb ;;
	rpm) need_linux_builds rpm && make_rpm ;;
	flatpak) need_linux_builds flatpak && make_flatpak ;;
	aur) need_linux_builds aur && make_aur ;;
	winzip) make_winzip ;;
	nsis) make_nsis ;;
	esac
done

if [[ "${DRY_RUN}" == 0 && ${#made[@]} -gt 0 ]]; then
	sums="$(cd "${DIST}" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort |
		xargs -r sha256sum)"
	printf '%s\n' "${sums}" >"${DIST}/SHA256SUMS"
fi
for m in "${made[@]}"; do
	ok "${m#"${SF_ROOT}"/}"
done
for s in "${skipped[@]}"; do
	warn "skipped ${s}"
done
[[ ${#made[@]} -gt 0 ]] || die "nothing was packaged"
