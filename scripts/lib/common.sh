# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
#
# Shared helpers for the scripts/ directory. Source it; do not execute it.
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [[ -n "${_SF_COMMON_LOADED:-}" ]]; then
	return 0
fi
_SF_COMMON_LOADED=1

SF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC2034 # used by the scripts that source this file
SF_GAME_DIR="${SF_ROOT}/game"
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------- logging ---
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
	_c_red=$'\e[31m' _c_yel=$'\e[33m' _c_grn=$'\e[32m' _c_blu=$'\e[34m' _c_dim=$'\e[2m' _c_off=$'\e[0m'
else
	_c_red='' _c_yel='' _c_grn='' _c_blu='' _c_dim='' _c_off=''
fi

log() { printf '%s==>%s %s\n' "${_c_blu}" "${_c_off}" "$*" >&2; }
ok() { printf '%s ok%s %s\n' "${_c_grn}" "${_c_off}" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "${_c_yel}" "${_c_off}" "$*" >&2; }
err() { printf '%serror:%s %s\n' "${_c_red}" "${_c_off}" "$*" >&2; }
die() {
	err "$*"
	exit 1
}

# run CMD...  -- execute, or just print it when DRY_RUN=1.
run() {
	if [[ "${DRY_RUN}" == 1 ]]; then
		printf '%s[dry-run]%s %s\n' "${_c_dim}" "${_c_off}" "$(_quote "$@")" >&2
		return 0
	fi
	"$@"
}

_quote() {
	local out='' a
	for a in "$@"; do
		out+="$(printf '%q' "${a}") "
	done
	printf '%s' "${out% }"
}

need_cmd() {
	local c
	for c in "$@"; do
		command -v "${c}" >/dev/null 2>&1 || die "required command '${c}' not found. Run scripts/bootstrap.sh (or install it with your package manager)."
	done
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------- identity ---
load_identity() {
	# shellcheck source=app.env
	source "${SF_ROOT}/app.env"
	# shellcheck source=toolchain.lock
	source "${SF_ROOT}/toolchain.lock"
	: "${APP_NAME:?app.env must set APP_NAME}" "${APP_ID:?}" "${APP_SLUG:?}" "${APP_VERSION:?}"
	: "${GODOT_VERSION:?toolchain.lock must set GODOT_VERSION}" "${GODOT_STATUS:?}"
	GODOT_TAG="${GODOT_VERSION}-${GODOT_STATUS}"
	# Godot's export template directory name, e.g. 4.7.2.stable
	GODOT_TEMPLATE_DIRNAME="${GODOT_VERSION}.${GODOT_STATUS}"
}

# ---------------------------------------------------------------- paths ---
xdg_cache() { printf '%s' "${XDG_CACHE_HOME:-${HOME}/.cache}"; }
xdg_data() { printf '%s' "${XDG_DATA_HOME:-${HOME}/.local/share}"; }
xdg_config() { printf '%s' "${XDG_CONFIG_HOME:-${HOME}/.config}"; }

# Developer cache (Godot downloads etc.). Overridable with SF_CACHE_DIR.
sf_cache_dir() {
	printf '%s' "${SF_CACHE_DIR:-$(xdg_cache)/${APP_SLUG}-dev}"
}

host_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) printf 'x86_64' ;;
	aarch64 | arm64) printf 'arm64' ;;
	*) printf 'unsupported' ;;
	esac
}

host_os() {
	case "$(uname -s)" in
	Linux) printf 'linux' ;;
	Darwin) printf 'macos' ;;
	*) printf 'unsupported' ;;
	esac
}

# Name of the official editor archive for this host.
godot_archive_name() {
	local os arch
	os="$(host_os)" arch="$(host_arch)"
	case "${os}/${arch}" in
	linux/x86_64) printf 'Godot_v%s_linux.x86_64.zip' "${GODOT_TAG}" ;;
	linux/arm64) printf 'Godot_v%s_linux.arm64.zip' "${GODOT_TAG}" ;;
	macos/*) printf 'Godot_v%s_macos.universal.zip' "${GODOT_TAG}" ;;
	*) return 1 ;;
	esac
}

godot_archive_sha512() {
	local os arch
	os="$(host_os)" arch="$(host_arch)"
	case "${os}/${arch}" in
	linux/x86_64) printf '%s' "${GODOT_SHA512_LINUX_X86_64:-}" ;;
	linux/arm64) printf '%s' "${GODOT_SHA512_LINUX_ARM64:-}" ;;
	macos/*) printf '%s' "${GODOT_SHA512_MACOS:-}" ;;
	*) return 1 ;;
	esac
}

# Path of the pinned editor binary once bootstrap has run.
godot_bin_path() {
	local dir os arch
	dir="$(sf_cache_dir)/godot/${GODOT_TAG}"
	os="$(host_os)" arch="$(host_arch)"
	case "${os}/${arch}" in
	linux/*) printf '%s/Godot_v%s_linux.%s' "${dir}" "${GODOT_TAG}" "${arch}" ;;
	macos/*) printf '%s/Godot.app/Contents/MacOS/Godot' "${dir}" ;;
	*) return 1 ;;
	esac
}

godot_templates_dir() {
	if [[ "$(host_os)" == macos ]]; then
		printf '%s/Library/Application Support/Godot/export_templates/%s' "${HOME}" "${GODOT_TEMPLATE_DIRNAME}"
	else
		printf '%s/godot/export_templates/%s' "$(xdg_data)" "${GODOT_TEMPLATE_DIRNAME}"
	fi
}

# Resolve the Godot binary to use: $GODOT if set, else the pinned one.
resolve_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		printf '%s' "${GODOT}"
		return 0
	fi
	local p
	p="$(godot_bin_path)" || die "unsupported host $(host_os)/$(host_arch)"
	[[ -x "${p}" ]] || die "pinned Godot ${GODOT_TAG} not found at ${p}. Run: make dev   (or scripts/bootstrap.sh)"
	printf '%s' "${p}"
}

# ------------------------------------------------------------ checksums ---
sha512_of() {
	if have_cmd sha512sum; then
		sha512sum "$1" | cut -d' ' -f1
	elif have_cmd shasum; then
		shasum -a 512 "$1" | cut -d' ' -f1
	else
		die "neither sha512sum nor shasum is available"
	fi
}

# verify_sha512 FILE EXPECTED
verify_sha512() {
	local file="$1" expected="$2" actual
	[[ -n "${expected}" ]] || die "no pinned checksum for $(basename "${file}"); refusing to trust it. See toolchain.lock."
	actual="$(sha512_of "${file}")"
	if [[ "${actual}" != "${expected}" ]]; then
		err "checksum mismatch for ${file}"
		err "  expected ${expected}"
		err "  actual   ${actual}"
		return 1
	fi
}

# download URL DEST -- resumable, fails loudly, explains proxy/firewall blocks.
download() {
	local url="$1" dest="$2"
	if [[ "${DRY_RUN}" == 1 ]]; then
		run curl -fL --retry 3 -o "${dest}" "${url}"
		return 0
	fi
	need_cmd curl
	mkdir -p "$(dirname "${dest}")"
	local tmp="${dest}.part" code=0
	curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -C - -o "${tmp}" "${url}" || code=$?
	if [[ "${code}" != 0 ]]; then
		rm -f "${tmp}"
		local host
		host="$(printf '%s' "${url}" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"
		err "download failed (curl exit ${code}): ${url}"
		err "If you are behind a firewall or allow-list proxy, allow these hosts:"
		err "  ${host}"
		[[ "${host}" == github.com ]] && err "  release-assets.githubusercontent.com  objects.githubusercontent.com"
		return 1
	fi
	mv -f "${tmp}" "${dest}"
}
