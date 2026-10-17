#!/bin/bash
#
# Installs Helm for the install command: the Linux amd64 or arm64 build that
# matches this machine, verified against the checksum table in this file
# before it is installed.
#
# Every juburr orb's install.sh has the same three parts:
#   1. tool definition: what to download and how to install it (Helm only)
#   2. shared install logic: identical in every orb
#   3. checksum table: one SHA-512 per release and architecture
#
# Add the checksums for a new release with:
#   src/scripts/install_hash.sh -v <version>

# CircleCI runs steps with /bin/sh when the image has no bash, and macOS ships
# bash 3, which lacks associative arrays.
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    echo "ERROR: Installing Helm needs bash 4 or newer. Use an executor image that has it." >&2
    exit 1
fi
set -euo pipefail

# >>> tool definition >>>
ORB_NAME="helm-orb"
TOOL_NAME="Helm"
TOOL_BINARY="helm"
TOOL_ARCHES="amd64 arm64"
# The default install_path, under HOME.
TOOL_DEFAULT_INSTALL_DIR="bin"

# tool_asset_name VERSION ARCH: the release asset to download.
tool_asset_name() {
    printf 'helm-v%s-linux-%s.tar.gz\n' "$1" "$2"
}

# tool_asset_urls VERSION ARCH ASSET: where to download it, one URL per line,
# tried in order.
tool_asset_urls() {
    printf 'https://get.helm.sh/%s\n' "$3"
}

# tool_archive_member VERSION ARCH: the binary's path inside the asset. The
# checksum table holds the SHA-512 of that file.
tool_archive_member() {
    printf 'linux-%s/helm\n' "$2"
}

# tool_version BINARY: prints the installed version without using the network.
tool_version() {
    "$1" version
}
# <<< tool definition <<<

# >>> shared install logic >>>
# Everything from here to the end marker is identical in the install.sh of
# every juburr orb, so change it in all of them together. Tool-specific
# behavior belongs in the tool definition above.
#
# Parameters arrive as PARAM_VERSION, PARAM_VERIFY_CHECKSUMS,
# PARAM_INSTALL_PATH and PARAM_CACHING. The checksum table (sha512sums) is
# defined after this block.

orb_info() { printf '%s\n' "$*"; }
orb_warn() { printf 'WARN: %s\n' "$*" >&2; }
orb_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Expands environment variables in a parameter value. The value is piped in
# on stdin: passed as an argument, a value starting with "-" would be parsed
# as a flag. Without the CircleCI CLI (local runs), the value is used as is.
orb_subst() {
    if command -v circleci > /dev/null 2>&1; then
        printf '%s' "$1" | circleci env subst
    else
        printf '%s\n' "$1"
    fi
}

# CircleCI passes boolean parameters as 1/0; local callers use true/false.
orb_bool() {
    case "$2" in
        1 | true) echo true ;;
        0 | false) echo false ;;
        *) orb_die "${1} must be true or false, not '${2}'." ;;
    esac
}

# Reads an absolute directory parameter: NAME VALUE HOME_SUBDIR. Environment
# variables and a leading ~/ are expanded, trailing slashes are removed, and
# an empty value means $HOME/HOME_SUBDIR.
orb_dir_param() {
    local value
    value=$(orb_subst "$2")
    if [[ -z "${value}" || "${value}" == \~ || "${value}" == \~/* ]]; then
        if [[ -z "${HOME:-}" ]]; then
            orb_die "HOME is not set, so ${1} has no default. Set ${1} to an absolute path."
        fi
        if [[ -z "${value}" ]]; then
            value="${HOME}/${3}"
        else
            value="${HOME}${value:1}"
        fi
    fi
    while [[ "${value}" == */ && "${value}" != "/" ]]; do
        value=${value%/}
    done
    if [[ "${value}" != /* ]]; then
        orb_die "${1} must be an absolute path, not '${value}'."
    fi
    # The directory may be added to the PATH, where ":" separates entries.
    if [[ "${value}" == *:* ]]; then
        orb_die "${1} can't contain ':', which separates PATH entries: '${value}'."
    fi
    printf '%s\n' "${value}"
}

orb_require_tools() {
    local tool package
    for tool in "$@"; do
        if ! command -v "${tool}" > /dev/null 2>&1; then
            case "${tool}" in
                tar | gzip) package=${tool} ;;
                *) package=coreutils ;;
            esac
            orb_die "Installing ${TOOL_NAME} needs '${tool}', which is not available. Install it in an earlier step," \
                "for example with 'microdnf install -y ${package}' on Red Hat UBI images."
        fi
    done
}

# Newest version in the checksum table.
orb_latest_version() {
    local key
    for key in "${!sha512sums[@]}"; do
        printf '%s\n' "${key%/*}"
    done | sort -uV | tail -n 1
}

orb_detect_arch() {
    local os machine
    os=$(uname -s)
    machine=$(uname -m)
    if [[ "${os}" != "Linux" ]]; then
        orb_die "This orb installs Linux builds of ${TOOL_NAME}, but this machine runs ${os}."
    fi
    if [[ "${TOOL_ARCHES}" == "noarch" ]]; then
        ORB_ARCH="noarch"
        orb_info "  platform:         noarch (${os} ${machine})"
        return 0
    fi
    case "${machine}" in
        x86_64 | amd64) ORB_ARCH="amd64" ;;
        aarch64 | arm64) ORB_ARCH="arm64" ;;
        *) orb_die "Unsupported CPU architecture '${machine}'. Supported: x86_64 (amd64), aarch64/arm64 (arm64)." ;;
    esac
    if [[ " ${TOOL_ARCHES} " != *" ${ORB_ARCH} "* ]]; then
        orb_die "${TOOL_NAME} is not published for ${ORB_ARCH}. Supported: ${TOOL_ARCHES}."
    fi
    orb_info "  platform:         linux/${ORB_ARCH} (uname -m: ${machine})"
}

# Decides how this install is verified, before anything is downloaded.
orb_lookup_checksum() {
    ORB_EXPECTED_SHA512=${sha512sums["${ORB_VERSION}/${ORB_ARCH}"]:-}
    if [[ -n "${ORB_EXPECTED_SHA512}" && ! "${ORB_EXPECTED_SHA512}" =~ ^[0-9a-f]{128}$ ]]; then
        orb_die "The checksum table entry for ${ORB_VERSION}/${ORB_ARCH} is malformed."
    fi
    if [[ "${ORB_VERIFY_CHECKSUMS}" == "false" ]]; then
        orb_warn "verify_checksums is false, so ${TOOL_NAME} will be installed WITHOUT checksum verification. This is not recommended."
        ORB_EXPECTED_SHA512=""
    elif [[ -z "${ORB_EXPECTED_SHA512}" ]]; then
        if [[ "${ORB_VERIFY_CHECKSUMS}" == "known_versions" ]]; then
            orb_warn "This orb has no checksum for ${TOOL_NAME} ${ORB_VERSION} (${ORB_ARCH}), and verify_checksums is known_versions."
            orb_warn "Installing an UNVERIFIED binary. Upgrade this orb, or submit a PR with the checksum."
        else
            orb_die "This orb has no checksum for ${TOOL_NAME} ${ORB_VERSION} (${ORB_ARCH}), so it cannot be verified (verify_checksums: strict)." \
                "Use a version this orb lists (the newest is $(orb_latest_version)), upgrade the orb, or opt out with verify_checksums: known_versions."
        fi
    fi
}

orb_init() {
    ORB_VERSION=$(orb_subst "${PARAM_VERSION:-}")
    ORB_VERSION=${ORB_VERSION#v}
    # The version is part of the download URL, so only release versions pass.
    if [[ ! "${ORB_VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
        orb_die "Invalid ${TOOL_NAME} version '${ORB_VERSION}'. Expected a release version such as $(orb_latest_version)."
    fi
    ORB_VERIFY_CHECKSUMS=${PARAM_VERIFY_CHECKSUMS:-strict}
    case "${ORB_VERIFY_CHECKSUMS}" in
        strict | known_versions | false) ;;
        *) orb_die "verify_checksums must be strict, known_versions or false, not '${ORB_VERIFY_CHECKSUMS}'." ;;
    esac
    ORB_INSTALL_PATH=$(orb_dir_param install_path "${PARAM_INSTALL_PATH:-}" "${TOOL_DEFAULT_INSTALL_DIR}")
    ORB_BIN_DIR=${ORB_INSTALL_PATH}
    ORB_CACHING=$(orb_bool caching "${PARAM_CACHING:-false}")

    orb_info "Installing ${TOOL_NAME} ${ORB_VERSION}"
    orb_info "  install_path:     ${ORB_INSTALL_PATH}"
    orb_info "  verify_checksums: ${ORB_VERIFY_CHECKSUMS}"
    orb_info "  caching:          ${ORB_CACHING}"
    orb_detect_arch
    orb_lookup_checksum

    ORB_ASSET_NAME=$(tool_asset_name "${ORB_VERSION}" "${ORB_ARCH}")
    ORB_ARCHIVE_MEMBER=$(tool_archive_member "${ORB_VERSION}" "${ORB_ARCH}")
    orb_require_tools mktemp
    # Only verification needs sha512sum, so the opt-out modes run without it.
    if [[ -n "${ORB_EXPECTED_SHA512}" ]]; then
        orb_require_tools sha512sum
    fi
    if [[ -n "${ORB_ARCHIVE_MEMBER}" ]]; then
        orb_require_tools tar gzip
    fi

    ORB_WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${ORB_NAME}.XXXXXX")
    ORB_CLEANUP=("${ORB_WORK_DIR}")
    trap 'rm -rf "${ORB_CLEANUP[@]}"' EXIT

    # Restored and saved by install.yml. Files are stored by version and
    # architecture, so a cache restored for another version is never used.
    # Nothing is created here unless a verified asset is stored, so an
    # unverified install leaves nothing for save_cache to save.
    ORB_CACHE_FILE=""
    if [[ "${ORB_CACHING}" == "true" && -z "${HOME:-}" ]]; then
        orb_warn "HOME is not set, so the cache is not used."
        ORB_CACHING=false
    elif [[ "${ORB_CACHING}" == "true" ]]; then
        ORB_CACHE_FILE="${HOME}/.cache/${ORB_NAME}/${ORB_VERSION}/${ORB_ARCH}/${ORB_ASSET_NAME}"
    fi
}

# orb_download DEST URL...: downloads the first URL that works to DEST.
# Transient failures are retried with backoff; a 404 moves on to the next URL.
orb_download() {
    local dest=$1 url help option attempt rc
    local -a fetch
    shift
    if command -v curl > /dev/null 2>&1; then
        # A stalled transfer counts as a failure and is retried.
        fetch=(curl -fsSL --proto '=https' --proto-redir '=https' --retry 8 --retry-max-time 300
            --connect-timeout 30 --speed-limit 1 --speed-time 60)
        # curl added --retry-connrefused in 7.52, and lists it under --help all
        # since 7.73. The output is captured, not piped, so curl can't hit a
        # closed pipe.
        help=$({ curl --help all || curl --help; } 2>&1) || true
        if [[ "${help}" == *--retry-connrefused* ]]; then
            fetch+=(--retry-connrefused)
        fi
        fetch+=(-o)
    elif command -v wget > /dev/null 2>&1; then
        fetch=(wget -q)
        # Only the retry options this wget supports (BusyBox wget has none).
        help=$(wget --help 2>&1) || true
        for option in --tries=20 --waitretry=30 --retry-connrefused --timeout=60 --retry-on-http-error=429,500,502,503,504; do
            if [[ "${help}" == *"${option%%=*}"* ]]; then
                fetch+=("${option}")
            fi
        done
        fetch+=(-O)
    else
        orb_die "Neither curl nor wget is available. Install one of them in an earlier step."
    fi
    for url in "$@"; do
        # curl retries timeouts and HTTP 5xx itself, but not a connection
        # dropped partway through, so that gets two more attempts here. An
        # HTTP error such as a 404 (curl exit code 22) moves on to the next
        # URL. wget retries both itself.
        for attempt in 1 2 3; do
            orb_info "Downloading ${url}"
            rc=0
            "${fetch[@]}" "${dest}.partial" "${url}" || rc=$?
            if [[ "${rc}" -eq 0 ]]; then
                mv -f "${dest}.partial" "${dest}"
                return 0
            fi
            if [[ "${fetch[0]}" != "curl" || "${rc}" -eq 22 || "${attempt}" -eq 3 ]]; then
                break
            fi
            orb_warn "The download failed (curl exit code ${rc}). Retrying in $((attempt * 10)) seconds."
            sleep $((attempt * 10))
        done
        orb_warn "Could not download ${url}."
    done
    rm -f "${dest}.partial"
    return 1
}

# orb_extract ASSET MEMBER: sets ORB_VERIFIED_FILE to the file the checksum
# table describes, which is MEMBER extracted from ASSET, or ASSET itself
# when MEMBER is empty. An empty file is refused, which matters when there
# is no checksum to catch it.
orb_extract() {
    local asset=$1 member=$2 dir
    ORB_VERIFIED_FILE=${asset}
    if [[ -n "${member}" ]]; then
        dir="${ORB_WORK_DIR}/extract"
        rm -rf "${dir}"
        mkdir "${dir}"
        # -o (don't restore the archive's owner) is spelled the same in GNU
        # tar, bsdtar and BusyBox tar, even one built without long options.
        if ! tar -xzf "${asset}" -o -C "${dir}" -- "${member}" 2> "${ORB_WORK_DIR}/tar.log"; then
            orb_warn "Could not extract ${member} from ${ORB_ASSET_NAME}: $(head -c 300 "${ORB_WORK_DIR}/tar.log")"
            return 1
        fi
        ORB_VERIFIED_FILE="${dir}/${member}"
        if [[ ! -f "${ORB_VERIFIED_FILE}" || -L "${ORB_VERIFIED_FILE}" ]]; then
            orb_warn "${member} in ${ORB_ASSET_NAME} is not a regular file."
            return 1
        fi
    fi
    if [[ ! -s "${ORB_VERIFIED_FILE}" ]]; then
        orb_warn "${ORB_VERIFIED_FILE##*/} is empty."
        return 1
    fi
}

# orb_verify FILE: checks FILE against the checksum table, when verifying.
orb_verify() {
    local actual
    if [[ -z "${ORB_EXPECTED_SHA512}" ]]; then
        return 0
    fi
    actual=$(sha512sum "$1" | awk '{ print $1 }')
    orb_info "Verifying the SHA-512 checksum of ${1##*/}..."
    orb_info "  expected: ${ORB_EXPECTED_SHA512}"
    orb_info "  actual:   ${actual}"
    if [[ "${actual}" != "${ORB_EXPECTED_SHA512}" ]]; then
        orb_warn "Checksum verification failed."
        return 1
    fi
    orb_info "Checksum verification passed."
}

# orb_temp_beside FILE: sets ORB_TEMP to a new, empty file in FILE's
# directory, to be renamed over FILE, and registers it for cleanup. mktemp
# creates it exclusively, so a file planted in a shared directory isn't
# written through.
orb_temp_beside() {
    ORB_TEMP=$(mktemp "${1%/*}/.${1##*/}.XXXXXX") || return 1
    ORB_CLEANUP+=("${ORB_TEMP}")
}

# Saves a downloaded asset for save_cache. Only verified assets are kept, so
# the cache never supplies a file the checksum table didn't vouch for.
orb_store_cache() {
    if [[ "${ORB_CACHING}" != "true" ]]; then
        return 0
    fi
    if [[ -z "${ORB_EXPECTED_SHA512}" ]]; then
        orb_info "Not caching ${ORB_ASSET_NAME}, since it was not verified."
        return 0
    fi
    if mkdir -p "${ORB_CACHE_FILE%/*}" && orb_temp_beside "${ORB_CACHE_FILE}" \
        && cp "$1" "${ORB_TEMP}" && mv -f "${ORB_TEMP}" "${ORB_CACHE_FILE}"; then
        return 0
    fi
    orb_warn "Could not save ${ORB_ASSET_NAME} to ${ORB_CACHE_FILE%/*}; continuing without the cache."
}

# Fetches the release asset, from the cache when possible, and verifies it.
# Leaves the verified file in ORB_VERIFIED_FILE. A cached asset that fails
# verification is discarded and downloaded again. The cache is only read
# when there is a checksum to verify the cached asset against.
orb_fetch_verified() {
    local asset="${ORB_WORK_DIR}/${ORB_ASSET_NAME}" use_cache=${ORB_CACHING} from_cache urls
    if [[ -z "${ORB_EXPECTED_SHA512}" ]]; then
        use_cache=false
    fi
    while true; do
        from_cache=false
        rm -f "${asset}"
        if [[ "${use_cache}" == "true" && -f "${ORB_CACHE_FILE}" ]]; then
            if ! cp "${ORB_CACHE_FILE}" "${asset}"; then
                orb_warn "Could not read the cached ${ORB_ASSET_NAME}. Downloading it instead."
                use_cache=false
                continue
            fi
            orb_info "Using ${ORB_ASSET_NAME} from the cache."
            from_cache=true
        else
            mapfile -t urls < <(tool_asset_urls "${ORB_VERSION}" "${ORB_ARCH}" "${ORB_ASSET_NAME}")
            if ! orb_download "${asset}" "${urls[@]}"; then
                orb_die "Could not download ${TOOL_NAME} ${ORB_VERSION} (${ORB_ARCH}). Check that this version" \
                    "was published for ${ORB_ARCH}, or re-run the job if the download host was failing."
            fi
        fi
        if orb_extract "${asset}" "${ORB_ARCHIVE_MEMBER}" && orb_verify "${ORB_VERIFIED_FILE}"; then
            break
        fi
        if [[ "${from_cache}" == "true" ]]; then
            orb_warn "The cached ${ORB_ASSET_NAME} failed verification. Discarding it and downloading it again."
            orb_warn "CircleCI can't replace a saved cache, so later jobs will do the same until it expires." \
                "Set caching to false to skip it until then."
            # Like saving it, removing it is best-effort: a read-only cache
            # directory only means the download isn't cached.
            rm -f "${ORB_CACHE_FILE}" 2> /dev/null || true
            use_cache=false
            continue
        fi
        orb_die "The ${TOOL_NAME} ${ORB_VERSION} (${ORB_ARCH}) download was rejected and not installed."
    done
    if [[ "${from_cache}" == "false" ]]; then
        orb_store_cache "${asset}"
    fi
}

# orb_install_file SOURCE DEST: installs SOURCE as the executable DEST. The
# file is staged under DEST's name in a private directory beside DEST and run
# once (orb_smoke_test) before a single rename replaces DEST, so a binary
# that can't run here leaves an existing install in place.
orb_install_file() {
    local dir=${2%/*} name=${2##*/} staging=""
    if ! mkdir -p "${dir}"; then
        orb_die "Could not create ${dir}. Choose an install_path this job's user can write to without root."
    fi
    if [[ -d "$2" ]]; then
        orb_die "Cannot install to $2, which is a directory."
    fi
    if staging=$(mktemp -d "${dir}/.${name}.XXXXXX"); then
        ORB_CLEANUP+=("${staging}")
    fi
    if [[ -z "${staging}" ]] || ! { cp "$1" "${staging}/${name}" && chmod 0755 "${staging}/${name}"; }; then
        orb_die "Could not install ${TOOL_BINARY} to ${dir}. Choose an install_path this job's user can write to without root."
    fi
    orb_smoke_test "${staging}/${name}"
    if ! mv -f "${staging}/${name}" "$2"; then
        orb_die "Could not install ${TOOL_BINARY} to ${dir}. Choose an install_path this job's user can write to without root."
    fi
}

# The default for tools that ship a single binary.
orb_install_binary() {
    orb_fetch_verified
    orb_install_file "${ORB_VERIFIED_FILE}" "${ORB_INSTALL_PATH}/${TOOL_BINARY}"
}

# Adds DIR to the PATH of later steps, unless it is already there.
orb_export_path() {
    local found
    if [[ ":${PATH}:" == *":$1:"* ]]; then
        # Later steps see this PATH, so an earlier copy of the binary wins.
        # -ef accepts the same file reached through a symlinked directory.
        found=$(command -v "${TOOL_BINARY}" || true)
        if [[ -n "${found}" && ! "${found}" -ef "$1/${TOOL_BINARY}" ]]; then
            orb_warn "${found} comes before $1 on the PATH, so later steps will run it instead of the ${TOOL_BINARY} installed here."
        fi
        return 0
    fi
    if [[ -n "${BASH_ENV:-}" ]]; then
        # ${PATH} is expanded when BASH_ENV is sourced, not now.
        # shellcheck disable=SC2016
        printf 'export PATH=%q:"${PATH}"\n' "$1" >> "${BASH_ENV}"
        orb_info "Added $1 to the PATH for later steps."
    else
        orb_warn "$1 is not on the PATH. Add it to run ${TOOL_BINARY} by name."
    fi
}

# orb_smoke_test FILE: runs the new binary once, which catches a build that
# can't run here: one for another architecture (exit code 126), or one that
# crashes, such as with SIGILL on a CPU it doesn't support. tool_version
# needs no network, so any failure means the binary doesn't work.
orb_smoke_test() {
    local output rc=0 line
    if ! declare -F tool_version > /dev/null; then
        return 0
    fi
    output=$(tool_version "$1" 2>&1) || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        orb_die "The downloaded ${TOOL_BINARY} cannot run on this machine: asking it for its version" \
            "exited with code ${rc}. ${output}"
    fi
    orb_info "${TOOL_BINARY} reports:"
    while IFS= read -r line; do
        orb_info "  ${line}"
    done <<< "${output}"
}

orb_install_main() {
    orb_init
    if declare -F tool_install > /dev/null; then
        tool_install
    else
        orb_install_binary
    fi
    orb_export_path "${ORB_BIN_DIR}"
    orb_info "Installed ${TOOL_NAME} ${ORB_VERSION} to ${ORB_INSTALL_PATH}."
}
# <<< shared install logic <<<

# >>> checksum table >>>
# SHA-512 checksums keyed "<version>/<arch>", newest release first, where arch
# is amd64, arm64, or noarch for a release that is the same everywhere.
# tool_archive_member says which file each checksum covers.
declare -A sha512sums=(
    ["4.3.0/amd64"]="d7f3833e2f74d7b39d54c0e82585a9f9defe93088b04fb7ef7c27e58c52e01f823d9a5b58d9c3ee8a56d1127a9a1552798c0c99846a1999dc24e1a42bf541726"
    ["4.3.0/arm64"]="31c12eab97c9163ed7c155e256279dadb84771bac907661043e4867f35f0abeecf09b1dd028126bd58ee30a23df71883b17d9ffaea5b6a338877485ae09a01b3"
    ["4.2.4/amd64"]="67a6d44ea29354a8a85dded383df0bca4f4ab562551a57710a327d867aedf211c20ec177794c63eb01833adb02a47da93bc68edabca635fe2bfa6eccdd56a72a"
    ["4.2.4/arm64"]="a990c1b49ee651d0bb66a99d7560222b72ba5ca1b328ffeb494144bf9a0b0ec32f72349250f3bad78312107c2a149f1585cde91cd35cb5b57caabdc045dcbb5b"
    ["4.2.3/amd64"]="350af2e5286f8c66627bc04bebf67b7c9cefac4f205955ca384c55e119bb7187b07e16af3b6bc880511958b80697db486a44dae598014ce4e702759cd472e7b2"
    ["4.2.3/arm64"]="b730d9b5775f10a4b0a48a64cfbbd3bab65411264af0bcc4620f1706b4d76b6cbce9e2bbea1a7fedd87e2b19cd473f8d11d2a1daef98a1747580d1258c49e9e1"
    ["4.2.2/amd64"]="b5ddaf536bc20e077f898072c13234d70b99acdb90f3a72673d2dc887f04b1a7aa943134eb5d64783ec3eb6ac107a00db9fc59c652304999497e621ac912ffac"
    ["4.2.2/arm64"]="7cd3f4c40aad7f7891f747034e05b71093a87473d524669189f23679b69b30da9e54a09c0bbfdb956a6dbdbaf3445f99219f80f5b752a8c89864f0af06eb0f9b"
    ["4.2.1/amd64"]="0b8a43d2946c7c3f870606c2dacc437fb910375cd443add5f1c9dfd9d989323eb4d51ef2a9beacfe937bda26f23bc83663500ae36359ec5417f731fc0a370cdc"
    ["4.2.1/arm64"]="bd9bc7aa62e15b23e0c22b475e32b589b56ba60212ebf11561cfef4a82822d288d3f6faca2cc06a1d97ac23d96c6702766dfc74561ed9fa0121a31f778e23eb6"
    ["4.2.0/amd64"]="b6c7ff257c8d8d20a73e94ed25302cd0f0e57956326f0d87b02d42e6b66bb6f4e162c2f5e3936235bce660917ad4659cf3233e0b936ec0109cf3f6edd9a6b4a7"
    ["4.2.0/arm64"]="7367bea1ecb2c05fdc2e24e86121cd5f76efbc0d1eb7b8da79737c8541450b4c3339bacc455af2a76de2f7fec2d97a80d8e16078adf9c66a294cee45c19b9932"
    ["4.1.4/amd64"]="791fad28d170abce1165ff7b2d0672a8c46c488e4f7daf4988873d8f30e0e149b0d09bc43f9fe3a998ed9219b4f3b526b129ab6ea0ad2a042f0496b05f52e5ae"
    ["4.1.4/arm64"]="8bae788776bc8580947ae22b8f7a903ee51ddad086907fe3a7da123b1fc88b78d89c6bb8c79738a5f71d42b883a36ee747c2ac5c41ebb9d83f351b46dee8b64d"
    ["4.1.3/amd64"]="bb883f057f4c6616cfbdf6679c4e03fc21997f37190b73cb144dd67a3a765e499cf32d311e60293abb44b6c6911639f87c9732202dd81ddc31567282eac01d6e"
    ["4.1.3/arm64"]="f8ff5c61abb3c779f912efe39df703791e70c1089746944f31090c622c3b75509e16ea2b0d3631f1232de4dbd4ba0e1385a718d51f120a3f9e80c0d1808655e6"
    ["4.1.2/amd64"]="500c389e3019dfe18e9992a65fd00a84def6bf58683f3d6bd3766da44d063f7fd1d3a213f587455a89e4d21081af4cef0800d0897da3f0d3ecb063184fb2fb03"
    ["4.1.2/arm64"]="43928dbc6a43e1abce9941ddf0d776e353011cf566685b9774d8f35d94305ffd4dd9c898e01ced8fab9b0c1ef5781d32870519ff252b4a3737d193da613d0986"
    ["4.1.1/amd64"]="ab60b1088ba6088e4e7212a7ec3a30fae582046cc5fbf51633ad7820fad00e194afc892f8cf96f82938e0b45ce3e87290d897a07dd9b367dd08509c40ef6ba7a"
    ["4.1.1/arm64"]="e94e79dac9d7a98bbc088833d74fccc6b761b4d7475788cc3d17143c011fc33e4e4323aa1963294bf3c1d59ddfedee9c95a38ae1bb3029c17b5a0d57d041d5da"
    ["4.1.0/amd64"]="93c00a314b4f0a7f6d73020013d171c408f40ccc164e96046dffc5889180aa38a4d27bb06d030f99b1adfcc2256fc9244db54104de0cc2258108104a047394f8"
    ["4.1.0/arm64"]="e7bc848e8a76d76b38b1e41850dcc08815f4edb1bf8f82f5c0fc1dfc4220392a333fc6e7fe234c0dc43d8e2122bb90fef223c3a9323704a48e06e4e93487772d"
    ["4.0.5/amd64"]="7f40a0fa0e47235a955e094a033ca4811b70b05721cd90bfdc1ea3780c2c82beced0b64a351f8add657de1967ab2720f8d0eff41552ccd451b4e510f8292d464"
    ["4.0.5/arm64"]="5b1f9cad23cd831b60953a3bf3e59d48a6cb1598bc85fb27d19862dc6cd17168878f1b9edaf5c664b7b11b6796c13bea93e774c6bfd63a97566bc071878297c7"
    ["4.0.4/amd64"]="e6277e5bc04bcf2b376ce3354ec2469d748e0721b768a8d38d68cef55a494863f014eb7629c370ac3ecb8efb1d1b0092026e853cb344061ead797973d8972db8"
    ["4.0.4/arm64"]="0ac5cdeafa5101dbd478c242b20ab95ef03dff62dccbafec3721676ac1f3c0fc4d26f4dc331d2ee977a71bbffda9b1de032f3699aabd4dbd9b5ff93fa5415b12"
    ["4.0.2/amd64"]="ddfe7308d797c59af73e43dd0e90a4feca33cef49e312dc65ac303a180d7a8c1dbf608dc4b47c18f054843689a46a1926063e69e9314d48e4aadaec654632703"
    ["4.0.2/arm64"]="26f099bdbe9ebde01f747300c20563922e043ee28350ff0172b30aa61de6718632fbbbbb3a0b89e978b3f4b52bd721ea00bc1ce70911a3cc1cf1d170d9ce1b38"
    ["4.0.1/amd64"]="40558c9c17a11e42410e242c6a1fdbb8b5818b1ab667a42cc6fa8a69a93eb6123fd26fbb16c536f02ab545e62b787e2dc379d5f1a8fedec101d71cedb9ff8ac0"
    ["4.0.1/arm64"]="908e8dda16c306f5bf805f5e138c165e5164c0447ee51aea326def00cd399d86db3312a5129240ea9d1d09f60658e17c582b11b8c83c3fad2ea8e7d24616dbc4"
    ["4.0.0/amd64"]="a90887a3bcfd7cb9cfe9a9a36e3b4f0ea7fa746a12233684b3d1a1f4e0ebe50a392fc10a4627acf88f10fd56914cb2e664f9dcb531cce7f266c78774ae0e7594"
    ["4.0.0/arm64"]="ceb0d65360a0eb891af3cb0c6af06987d11999b4e43552918c3aa84b22aa087df48bbc01df5fc97a2548e4334271ddc8d9754e38ceec6d500cd733e32126760e"
    ["3.22.0/amd64"]="35c4602542e0c31c7bc1011413cd20266702a3fb31e2f03b2f897fceb9b1d4d8a2dd10f428fd29beeefd1e3e92bc9d7477df42d7fc4987996fabd3bb7675f20f"
    ["3.22.0/arm64"]="c29cbd683feeda1bd5f642d420b303fc25ff78f1bcd138a722fa9241a333a5339cc8c9943dc7ab4b58e16a4a68d0522262b66548a2478ede58ebca4ef08e23a8"
    ["3.21.4/amd64"]="9411745559f792a4cc4df164a5997633848250c8978cf8dd337ea25379e6dd6eda46d5706020f2b1a00055f9190f5ce9b91200892e55ac6514f7ae95b507c53a"
    ["3.21.4/arm64"]="ee1bcb131f6cd22bcafa12774a407461a17e167286f62750712fee243e24de1f2dd43295183923c9c0c1b9790917dd95919609e5cf0efc6ef9a078b653b9ef51"
    ["3.21.3/amd64"]="a646245c80a8f48b07a38704e6b9abe701415064126fa5e4f616937541f7bd62608d1ff78ad06095714e71d5026d6936fba81a96162ed8a426aae25660d7727e"
    ["3.21.3/arm64"]="e13cb647d9f193b7e06b1c07741736490e38bdb5b1742b4831e38574d2194370210dd3d7a687f3458b5908a168cf3badc8e6b635ab824f6ea2a07745449a9395"
    ["3.21.2/amd64"]="5303e3fbf1e830501feacd10a2bf4b45893dd931338ca646f2028faabe3e337146c485f52821e3c794aa46418554e0958986c3ae634e88dd573cc7a5c7b6c142"
    ["3.21.2/arm64"]="549f5221c8be948fe8d1f78c4e74d0042462b27c0d188ccafd63f1612737c2d5118ca45f6b32b771188f876bbc2b5f030756cf867044a8758ad015bfd7fb567c"
    ["3.21.1/amd64"]="ece4d61eeb94c66c6d0b70948b39f93bd6dbe74a70499fadcfa5792fef25b38ecd09b512cec438d6136d3d633d4983e5b439e2989bfb189442f3b797e14b09bb"
    ["3.21.1/arm64"]="686f76ebd3f0f02845ce2b0d9c2aa0ee85e285523e287da57d2c5c4ce706658dac867f82125de7c3c45d9d6247d1f2ae3a9c9bcd3d36a8b497079d5254c332b4"
    ["3.21.0/amd64"]="7c43f697098c8298e13642215beefb849eb09ac2ff149f5ce58c582658354b1ec8aa5520f3d7c1b69bc4ccd249e7be3be9f744998e9cbbb597b59cc929eeb691"
    ["3.21.0/arm64"]="471e2a08a7025c121e3fb7347cb11087105af0488e5fd9fd3ef58b02cfac2eb721caff338b31f29759e008f3c14cbee8516f2ae118e3aed61b4937d41dc29382"
    ["3.20.2/amd64"]="b3d23d547923d16dc169d55450e780cae8aaf8eba4bb0e6d603f8d38b9eb50b48ae5e84d0b5ac9cad4047827207a4d036937394d9fcdc842b0618d30f308bed3"
    ["3.20.2/arm64"]="fbd0912dc8f66f8da3a6333fa39aaf51bc9164bd5db67565f91c24e1fd06fb7186fff62cdc185d1b902eb0a535b5df84fe78c31b39b531edbc86f627014b31ab"
    ["3.20.1/amd64"]="284d5d63579fb85a454a36b1b378523c4359b0b96b07cf875869493d66e5a80d6d99ed0dc9c36f1e99867dd3254c8c29e75205a8f39bede900398d8f9bdd7d22"
    ["3.20.1/arm64"]="40ecd8b2062be2628f282608b68bb2add551e3ccfaac5d00b89a83153ea44f228df88e228249fb1b85c3aad05a1288e15b92a6c2aa70a26b9f26e0500304723d"
    ["3.20.0/amd64"]="61dcaa64585ec01ae4ae4678934bef883153be13fe7d0f2ce9e5537c7c3d182e0942e3033ba98878f1754222ad0379f397e8c82c0e2041ec43879e3ad82b4940"
    ["3.20.0/arm64"]="9a5550cceaed2aa2fd0ef30def7388c37aa7ee5be3f59e8425dff26e08ddb29a444455ad8c31a3a0e83ac5727faa3487b1f748cdd21369f870f1a080f7567546"
    ["3.19.5/amd64"]="4f7f399f0df7f7e26a72373281234cacaf653a8d84dc9ee50947d0b98cccc11864d2b46bcd41e6a9cc8ab17933d9ca48ebdf40609c13b9a6f8baa5a81e2e2207"
    ["3.19.5/arm64"]="12399a8d451e641199534a740573015b4e457ba8c089a06f2f71ac2656dc25c0bb360d886fbd647eebc3157f9471a4324a23c48f57e98123c7a29ce8c9a59ff4"
    ["3.19.4/amd64"]="813c3472a18542d62ec1c656dedf57dd954964de20b619be548f1437843b5b5b7df156a31c29b1e86c7397188501a744d4e2a20aed4415f5d104a81ab779aa11"
    ["3.19.4/arm64"]="02e1243e2dad2e838eef98497d86fdca10d0ac9e1d6deac22c5a0816bf3e31ac7fb750291879eb5343d6765ac886256486156b5ef0abfe9c3b4a3d16c83f0774"
    ["3.19.3/amd64"]="3d713f3d7b521630cf95d32da379af09a562548978faed2d8e34272815f901e6565f2612fceed4e5f97723000e6516e7269ca607fe742d5bdf67be4868e517ea"
    ["3.19.3/arm64"]="3432b9babb8ae585ac5636077a1a11e9cc047f69dfcd536619969f07f887b2877307b5535b72ac6cccce47a8ed3e03d03d68fd993815c0c027af135d83997ec1"
    ["3.19.2/amd64"]="6b026936d05e718bb1cbca39d99b722452f3d26c9f1671307eaca17d34de66fcb5d05cc52f8380cffdba4a423b18f3940d733b2697d1cb8888a374164d2ce3b7"
    ["3.19.2/arm64"]="35bbc285392bce3390cf45f6bd7ac181a9f6291a4f826d148e1bae0c2c642e8c77db605d59a98d5938dbabfea350351050ad3c989ec54c0e4ca02f2b6e01c718"
    ["3.19.1/amd64"]="820d49538739911ad75a140695c64697f97431c07f5d99af4b986196c71b4d64ff6b238b6fad9b7ec978fc87bfd94c0061d07d18887cf551142cd3d97be5e607"
    ["3.19.1/arm64"]="8ae39a82cd8418798560977b941dbb21cfad5f315695237c26dc019ef679fda1fdc0932cc5c1c5a4afce872b8418e5d39e002f3e12e6880fb10e15d35a9b7ca6"
    ["3.19.0/amd64"]="3e49884159f50a34299cd9debd160bd493834aa1d7dd16965d7aa5cba96e677a7d0e3763fdd4cc2ccc6c4cde68c07dcbca9e21b0837598a0215acb4ac9814ef5"
    ["3.19.0/arm64"]="39e33c25e4a87b48d70ba91c1f91f74eedf34929d2aa7223917c9c27ea89e0b107224a601dd05659fc142f8047f70d177964439962c98781ba04398e0487e39b"
    ["3.18.6/amd64"]="c4535b297bc609b9076c3905cd05fa49469444db5a80e89cee849eb280e37cc3f553350c42ab1403c13aa5cdf4d85af6321463d208b6567fa04242a3e17b5909"
    ["3.18.6/arm64"]="c5b36f51e0c1d4c9b94113936d57b185b05c14cecea0c4d269eca84bc1350a989d381e67aa458783f5d1ec207af7cb259094d2341b8f2d1ff1c875d010452f06"
    ["3.18.5/amd64"]="416691338a5d9b2e5b4de8390b22494ad4c5f010209386299a8235aaa000014e55bd6211f81eb811a3a94a10ebe1f8d6c354dfdbf85b1ace9a16c5ea070fff3c"
    ["3.18.5/arm64"]="2a393409eaaa2670584420fad82dec57eadac28858435193b51243205845f5e91c6d0339ae7036bc79c628feb604cc76cccd7284c0aecf8ab2982feb19e2ea4f"
    ["3.18.4/amd64"]="bb3ace41907f46086669316b1c2d6968ad3388f9979d7081578ffec78eb4b8c8809567ad229135f263e911b2140929142078bc5eed264fa620b77285f6a38865"
    ["3.18.4/arm64"]="00de904e8d19c0af2f37a35b378f6cc3181937e415187f76f3b41c77773793325534f12494dca9cd057515baeafb098d9137bd282aec5c844bea97ee135cd892"
    ["3.18.3/amd64"]="06ee2ac01320c8ec13be48c5a2a6f543868da40f3529989268a9322dd75f75e7f58f3340cfebac2cbc2f22b5cf33f97b87f9229b5ee81578778170c13222e1f0"
    ["3.18.3/arm64"]="0132449908d67f7aaf6a93cd172e833e3f8ab49080c9785ebeb4aa2a8d5abc6f21551a9e2b87d7e2fe0854636c04c9fccbb61dd565568b76697c0baed8b8b8bd"
    ["3.18.2/amd64"]="212a1a734b2bf9c051580937b6e624227a05c740792e747da06b3eab7698d61d773f9f974ad35c709553af789b045c1951d749e9fda0aa7a73b16d4eb6fe609a"
    ["3.18.2/arm64"]="f63b60f8c6f519f135caa8d3b357322ca3c8bbce3306c2cbe6f847547efd9852bd47bc10242da052f2ffd20b7761b857861006f25452e231854b424dd897c155"
    ["3.18.1/amd64"]="6cdee0d92975c134196dd9f780003f10b3f1c018472e538226780155d221d32e5347e584f672eaf8b568dc7c70ff6b0537d1e4d3a3a42c95a56fa2634579d961"
    ["3.18.1/arm64"]="50d83a832dfeb2fc998003e0fb1918dd29b8ec440e36c17226f1668a331c772ea7a094482f71d2b078ba597fdbef784f3fd092c8478e71ea8bf8b56fb8ea57a9"
    ["3.18.0/amd64"]="d2b35f68e6cda73978501cea5c1c17a3b58eecac726a52c9f8d68419aac91e05da3c1f23ff177a3104239d033076c958481a4ad22c8a607521a31fb8e6c56db5"
    ["3.18.0/arm64"]="774dd90fc24d1ed273c1c8a8350f0add5e18e762d1090bda56882336d39e6bdc69768c8499bcf790bce42feed9ae6f52f9cf017194d168e194b5be7b1dd0d455"
    ["3.17.4/amd64"]="2abf030df1eaeda7dd4da6959afef886668800f41f2d79d3b8afb7918e1a3933a012932aa9135c9bad4a8ad59c43994da106c2ed4534bc72dd960ebc4ebfbe61"
    ["3.17.4/arm64"]="2ca641897060a153320d320f3e1d9a693d1881feac7a89c9f7d3c841018c5015c2096278abedfd2b0604701f227db18409d1accdd34906e7f9595ee615abfa32"
    ["3.17.3/amd64"]="e9180958b65b3c4c0fc1d6d800bd5b8d10297144d868154f3103ab400006f3b7fe72c792d7ca7576872671b12498c8b7496e3586fa4f0a8f797fde500ccae37a"
    ["3.17.3/arm64"]="b7721b228a5bae808a6a2348a5723d48a74bd10574181c28ca77e8763fc32b42517993a85d2402252031fb25a24318eb24a0b8f9926913feb9ce1c3cdfece1d1"
    ["3.17.2/amd64"]="255231f71bde1497290c37d27849545316f02027d5c8f2b04631276f54933778ba6d45251938fff9585830a2a4043be0eac01a51b578de135fcb85ccf3dd50b1"
    ["3.17.2/arm64"]="40983c49c444c3307a64dc61f7a5d7f13183930d5fbd69bd5105896530a197ea9ce55d7b2f2380213f4574295415f0f89c7bd94db2a17abbabe436f5926b32d4"
    ["3.17.1/amd64"]="969aaf1b01e76a17455cc2f7f218706da5b155eeefcb0da970333328357d933fd4b2de34f0c91008ddbf80923eae5637ad849da0d485e5672dd04442598bc967"
    ["3.17.1/arm64"]="60203dd818845cddffa1592047406c096662c3c26ae185c21c8c0974daad499244dbf32d2095f647bf2a6fe295945300ffc59407db7d8e1cbaf508423f19efe3"
    ["3.17.0/amd64"]="6c2cb04b0fdba949ad64e20b7ce6eeef453705b6c10c740a3b7d69162fd86cbb4e5a668b501980f12e77212682374b751b6a226694cd0c13816b7f09e6560743"
    ["3.17.0/arm64"]="bac0471c0351b1c6da9783e2cf06ef885cdad2db95bea329c42a395257463ba0cf255c28a484b9c2bd42cd8a131242b0e954ca03c23dfbcb32a4c2e6d1925585"
    ["3.16.4/amd64"]="71c83f0a09c460eb9128eab58d45798611d6873068f5714ee81cc6b3a4526b6722c41252a34dec74aa136d5d4ffc5116bfd0418e737da4f3b4937e720ec54a8a"
    ["3.16.4/arm64"]="5fb21cbca1f2530ff2d2e53a0cd4ab578e74cbf92242b20e33974638ac345088434b7135e23ab63c2e1e589ceb1218bc5e798d32bdd6a4f657c1d51b1a004ccb"
    ["3.16.3/amd64"]="7c7fa18fcf276cd1cafe03b68f9b48e47eb323f2bab673571d584a7ead0f5a23c1f0833135a14395ab129e4152d6bde3621a107e72c55ab48770ee156abc0375"
    ["3.16.3/arm64"]="0fb21ab3cba409c6248ba14a0477abf4985ccba12d37cff71ce5a811f22e51c94747b5dbabd8fb90efabeb48092f0d961e37fdbc8e0b2cb7dde73d388ccabedc"
    ["3.16.2/amd64"]="70b266eae0ab01826a97e7e2a46e76b7ed1d699b9b718f6e7239aaa6b95e61dc0ee2ece97e91020023c769447d35198c700b0df5f63d9a3d8efbbe6e434b69a6"
    ["3.16.2/arm64"]="4a049ef76f4d880e6154415bba4f79fe86c7b362e60eb834e5bc3043bac1ea6ecadaf910c0aab8aa61f760c101f6d1ffb7ef6c36f77bdafc26e02217719caa44"
    ["3.16.1/amd64"]="3caf691686547d299f5bd575b155cbc841909d5d1fb7661a1431a72a9e0868788874c71e97bdf8f32a805e266c2d1f94fc7b9be6fd783912697fdc53329cb169"
    ["3.16.1/arm64"]="cb91b7d56cd29bcc0d7a700071bfdc09c4d720c24bee6657b8d78fba253d6d3837632daaaaf07a9440884a0a0598d8daca26977de8464e5365c917c2532ece75"
    ["3.16.0/amd64"]="910c1ab302ed2806f73ddea46d206a245daadd7da331b42ee90ca7baa40e3d187a4ba5fb906f69b89caad3f48c566643cbd8ab0996a0b8d3a3fb194183000af3"
    ["3.16.0/arm64"]="dfd90d17ab3d135dbbc7f95afb1bd68887718559556a2bc1e03141bc298ebbe7a78c1a291f72097910b6ada699b0919b9282378f51d59ed05f51e5a2ffffebb3"
    ["3.15.4/amd64"]="37a696e9629bd2d088e69130aeace2bc3380dfa5b0f52900346903f3ac6e9e13d47db279f173cd0a6bb8510c33cc1ef9de0fcc53d953079fdc6b5e53d3daf130"
    ["3.15.4/arm64"]="20b7218fd65a4305f4d9af42c33f3941de630ee94b737cf8a8dffb329cd0414c1d881bb14442d4f7668e1ffdf06d8bf90d194a13c5f4d3598af26340bc80f1c1"
    ["3.15.3/amd64"]="93db94da6e385b5b403aded651adc7dd3fcbbfa01d42e39c91f656be929d0bed2f6fc8f9b32a4e1492c0988f32dde82b7cae29eec0ca03543da1d05478e50402"
    ["3.15.3/arm64"]="1d2b19fef6345a9f8887f0b5d352e72ca63df8309a82263dc3d90f63781c1c81d5c0d40a5f32cabe1271f41b1fb20e7060ce50a2be4486fbc98324d08221ed72"
    ["3.15.2/amd64"]="3982086bb493f27fbd78172878945993f12af33ff1daee70c30512790176ee8c3d99a5c0367ae183ed5c47065c542d40aa1582ac907cc181ad86c248c8ff5e05"
    ["3.15.2/arm64"]="1ebd71b685c7d7ab4b4a0b6570d16dd5c066e55844213a3aa7a92737483b6eeff35f1230bc4fb96c47257156617debf127a77b38542b83bc7fffe120085094dc"
    ["3.15.1/amd64"]="2bad6de17b687e8ccfcb95b6b435ef467f023f9c52ef129d3be306cd7a662d947dd925d2e52e4ea06869faf9f5ee363156e758d1af24c1f68692260ef58b9087"
    ["3.15.1/arm64"]="ad726c925c0948ee08c46e853fd963195b1557cdafa4d535c9b80e06ba880a8a4efe21202b7582b295931d5cccc6cc1c45a3ce27639b7221fa8fc71b1f7ff4aa"
    ["3.15.0/amd64"]="f79ffd4f7d387a7a4bf7982cc3a4fcd8d8be0f7734a6b65643fc972eac03f4aa3b905ee3ee6b04903ade7877532ead20737c3427d38ab23dcdc28a67fb2a997c"
    ["3.15.0/arm64"]="6bd28b21795ef17d7935ce1e3ed47ef728b2d351031d1b8fde7a63e4975c49e17bd9bbbcfa9fb97a38bd298fd59b907d422cf3d6feec0e7843671435ee3d6d37"
    ["3.14.4/amd64"]="21a0a1db41c0ced37d29bb64a20af32f0795378cd9206161a64c3d2fdd3b9263f5b51b702eef4b62a7718ecfe605f069deb77897fab18740678559d40afb2c03"
    ["3.14.4/arm64"]="7292e56d21c21b9afe1f9e0cbe53bb8d8a88e45117af6d5ccac2759d2d456189aee725389ae94af8861e88ebb41e7d8468a4d51be0ac71649c7be66849d26c21"
    ["3.14.3/amd64"]="830d2758870c8b010826abb2a1c5fa81676df1531fce6df5489724e646d9a612a6508af6b0ba0a6b56ecee7fb50dfb6738c312ab494724cbe982652fd7b6ccfe"
    ["3.14.3/arm64"]="d0d6aafc18e8ae5560f0a3a6d825e859631ff76fae79dcdb48a0ea2ec4d65538f9ac74ae81017f1ec5c83fc904d598320a4d0ed2a048076d01776d1327fd0bc8"
    ["3.14.2/amd64"]="58da09644db664ae007a7e5f0fdf0b3a346def3326a4b7725a5d4251b88b7e11944a5bd18f1162882e6c5812016e27d18bfebad2290ba0dda85ce5eb5c1d3fe3"
    ["3.14.2/arm64"]="3b4dac70c9d0dfb03ff067924820f8f5799bd3a03945441ea435ce2003100441170f1b6a490305a5295b41187b0756f11b9c24acc688f76cc14fc2a88facb180"
    ["3.14.1/amd64"]="1293bee6e3b3205b35bd285fc0114ce8254de28922b8c4484f9baec747c9896b8efe082cf4fe2ea5dcf61d834d56afce3f87c67d9a087ab7bdc0c5838c285b14"
    ["3.14.1/arm64"]="2cdd7f1fc5620b2872df02fa4bfd75e7a772b23a8fcfcf37fdbad09e092c086c7aae11b906525192c5adfcd048874e32ab67491261b419786cc0486100a69b52"
    ["3.14.0/amd64"]="f128e4f7ba44913247041813ede58361d8c29d35ea3054eba666d0ff6651f32e5389bc371c246ffa61f058de2e55bd344a6aad7d249a7cadc150ae3e7952f4db"
    ["3.14.0/arm64"]="ebcae86472ba7dc7c2447130d4fab23cf9febe668989da58da547b6e1503f26ad7290b587bbbc0c2ffab690beb1227c2557cae072cdf4182610dd50197eb8f90"
    ["3.13.3/amd64"]="fca98aa0a1c601d2bb7e006637d8a21c0172ccca1f9198292d23244b1df0ec515672b765d3de56046b4ccde04a6f44d11d7121a3f75846718301026cb56f38e7"
    ["3.13.3/arm64"]="5e1dd85cba9d13f7c47dd438fe856d647da6cd85840ee7679ae62b1e03a2ef3d6f0b08a7e11bf1a8ca2022dfb0b5670d4eccfc7523da22ba10041ecf232fd90f"
    ["3.13.2/amd64"]="d5ebe06bae205fa0c2f8dee472d09e4f6e441cbfe80f00274883610a1dde3338721982cbd3f61be94c2fb2bdf43a1aaa8fabc563094f667272a50b6f3a0ade42"
    ["3.13.2/arm64"]="e5b199e4c7f8dd27f39995c5daa891eb1285d6d497117b29d50e3d8a2251e08437e0c38e49dc7a5e49ddc810d6f8596d65350bba9666dbc053781d68954db5f5"
    ["3.13.1/amd64"]="174833971dc0a99a2e57ff2c3d7e306892375d987e13e61f796a3f716bfb6d6ca751e1fc0db0321a8a3dd613ea170339daf522640977aa7bfa90e07cb5a8f1ed"
    ["3.13.1/arm64"]="8165722beceac80456b6b7c1e5383a54b2508da27445c5c8cccf01d6e2b903ae1f7cc5bce007816eedcb1208d436abda10fb27fe8b5dad9a7a47dca86bcd1440"
    ["3.13.0/amd64"]="31c3c958399b424b30d20f2e935e62ac26b995b82d475c64850f5993f9a9b3ff6a606712bc8ce05d4eaecdc86b4b4de14f8fb8fcf4aab284774a6d8a4fca45d4"
    ["3.13.0/arm64"]="dd4459b0c18ec1746c25b8a0c831b2328bae57516ee0d8822c4e8e40ab2d80f9342184659d3d50b14282717ac78744c19a03b76d808eb418deceee12f002704e"
    ["3.12.3/amd64"]="f8652c7f62b126b547c62f3355ebe9f77b7b2dd53af7f4ca84d4182023157fc2fad1a5f22e4ecf5dfc3b6a1838df823743132c02deb3a120c6c66eb9aae7e5ee"
    ["3.12.3/arm64"]="d28447e87035cdd52899a50d0647dcff33ecb7cc5c5699e8cefe6ca5b5bc7cbb1e3870a3f6512e7eacf5dd99681084cf542bee1bf1eb29e23776db27718add07"
    ["3.12.2/amd64"]="8037f7d98c7186ced0f41e18056717507ef66ff4df7171e9775e56338311a31a1290db8c2467f259a7c7d99d636b9360577273da50aa7c250a3a02d16a900857"
    ["3.12.2/arm64"]="4e2c8ab6723c67c31492178620b53e43ab9e883658110af12decef816c35d8d38d47aec834f0b5557a3977d04f937ab967a8d5e16d8f9c1ef976f42f96fe7344"
    ["3.12.1/amd64"]="b273d3dcac9012ee07e6e390d7a91fbc3848de1f2623edd8e2d414aa434de01df4472b29950e2556c78df221ab1bc08cee9d54ae91b033b512004bd0ee5c4730"
    ["3.12.1/arm64"]="16c864249516798818518c1ba6a94ab66409c1cf02efa1ba50bc28fea990adee6e45ede421cbf4cfdaceb3cdcf314c182a48adeb6879deda9321a04ee6be20b9"
    ["3.12.0/amd64"]="fb8963b02c59aa10563db54a5f30999be308d23a4089eecece9f7c0a0afa03c3464cf3982c6db309985d2c87a974a305fce7e13ee1b2968807cc217c4c5a7846"
    ["3.12.0/arm64"]="f1724c4e5f0ef2fbc60eeb0cd9664bf704348f7a4c84a480570cfe5c55c3903394f1d4bbca2bc15a8a305d11747717ac3724a407400edae5964bcf2c62786445"
    ["3.11.3/amd64"]="16cb719e5a5a695721e4add23a88222502c84c466ec98d8b6bddad04ddb5f960b74cff116143f0b1029ca2093642656313e9d950496f3e15576bc17cacf2e47f"
    ["3.11.3/arm64"]="7dc9e74e242dec62265d111f19da75b10cc64e27db9d535874d915505bb9b4f73c5afe46ecef58e8357734e930e2f1e442eb4ca8bee8cae148b89983abdad354"
    ["3.11.2/amd64"]="b29c145ac33d03c7513797afe4caf1ba7f5e9b0555cc2b18a0df0dffb3a20d8ffc90dc9713f11df8237a79a80f716ed6374a47b33484a66bfbae93a66a3cf23d"
    ["3.11.2/arm64"]="83bca72e16b92969b921292290919ce12402a64140a66e91e51e2fa5be45c04ee2d1daaf425aed5f02c5d3f4d54125c1d3e4299b8d1d7bed8431e297e948e61c"
    ["3.11.1/amd64"]="ded2f48c530a9a6b6cf863a83b8a22865958191e2b58e2379eef9d08b1ca307a90b944d25d27d53d1aaffd55aa24ca5ecae7c2e77313c2639af9c0ccf7b00c2c"
    ["3.11.1/arm64"]="c8cbfa73d1fa3d5065ff13397a419f6aa8282b17026db31c6e346e569e163ed6ab1b6388f17d726d750849866ca9c1aa7ac1a67e39656d014171c45668fe19e4"
    ["3.11.0/amd64"]="76bfc6e3d3c41ec11b4c85d268d836994ea3a9db6be5e71cb9334520ff9e1463d6a3c9314fe334246a5bdf3629c67a56cd0cc60ae058bfb34946d1a06301360d"
    ["3.11.0/arm64"]="42e61570d20a248a768381edd4b5937c35289c1e4651c703898f452cd14982645d1dad178f95bf281a0f33759ccfb72355bbbbcf8c804a30a9f910de7f265ef3"
    ["3.10.3/amd64"]="112c78fdeb5bab739f43c67126b422369fe3df3bbb0399682ac784451fd24801f6902da927ebcff86d8ad767be9ccfaaffca1b221975390df6a430f12c4d40db"
    ["3.10.3/arm64"]="80bf08f225e16df68e8658aa7f67f866a11c5e3aee294bdffb735a78a80d29ffa6b7aad51fa926f0a565ec1d237ca3363b86ea4ea9de62cad6e0a0f813e59561"
    ["3.10.2/amd64"]="3fce40674407cec966e329aa6dc93d1ca8fcd8dca7171d5b532a82ccae134174aaa54aa9e75056bd58f5a5a4739234494ff591fc2f46ba8558953a82cc93d4bf"
    ["3.10.2/arm64"]="8140eb87b946a4a546a1f509e4ef51c641865c074eea5c62f962204c26141a39c73a399c6ca5f8d4374b7d5d37e272ea911d721abc3be8b639352a5d84b3b2c7"
    ["3.10.1/amd64"]="56c89e4f0691ed9571a8a620ddba5d56ad6effe39a275fc88c942a7c97878fc2da6eba927f21a627bd704f91377c25c22d63864afbbea168cf628f532bc69e5d"
    ["3.10.1/arm64"]="2af30e0accf2c9621da895624d8ffde9b82def0df601aaf3cb994bbaa10b385d18c049182d8ca2a5160e7338c5516c9bd3c13f662e82c8eeb5470df0b7ec01f9"
    ["3.10.0/amd64"]="b8e6689287958ad70d5e905b88c0d90d36ce0191fa75e58642bd0266b77e5f68e5b0fa2af06d41ce3f57b9b0e9f2bbd5d829a34d0a2bb06c57244012d2aa54ed"
    ["3.10.0/arm64"]="2cdf92e6483f7c8d50f5835226e6da52fa3fe597428f9d239290a643bdb51fd7090e2254c62e986d13ff4478358636564b12f032cba7b199026d075286c4fceb"
    ["3.9.4/amd64"]="e5d97b0a9895e5dc86d74df330286450846b76b7218d6d84dfe810ef10d961123bc9e1b4c140377c7f1839bdc0d60563df262f6f778e81557320a6c596b4d1ed"
    ["3.9.4/arm64"]="5c4af80993b32f97611ef525acc7f7250b668f0642395c901f3ed153483d1cfeef39ce3e404e785c279db8c381006021b09da3ddb4d21d2d113adba605d6b569"
    ["3.9.3/amd64"]="4119dc520ca0aba424a7b3595ce8533e57138635c219841305b3d14f206a175e523804a246bc41b812cc8e88fb306d5db4278d0157dc419fa7839bc36a2c224b"
    ["3.9.3/arm64"]="1ed135baacf435ede8f27e8531ffdc514cbf68899e856f5ad965e6d12a47a52e411d9336e830a64bcb307b7fba18e65dbea3cf7f0521ceef0241168883f434e3"
    ["3.9.2/amd64"]="908d704c1b0c0ad2b59e20245786c385f3997c4e25d526157511cef9a0febfb16851fb439af53ae0bf6a9e1ae97f96e5162a316bcc09d08f3ed4da15cd2f652f"
    ["3.9.2/arm64"]="ee09c547d4d9a19853edbf9bf0828c8aead0c898d95debae640c725a46a210a850f6aa3e8a7ce1a1c1db9d863934ca7fa7ba3184f3fb5b2efb3ad42c0992fea5"
    ["3.9.1/amd64"]="580666e8c4cdcba473c8e425006951933fd497d90e28ee020911bc183a576765c42738d8eefc6f7e9d9983f16d81c58de0db3b2e79737abd1853a871c2d27b9e"
    ["3.9.1/arm64"]="90b570f179be6d71b3421e2a6772549d751d555d59b75e495efcec38e6669a49fc6df35e0c5b4991ee4a5168d7fd614e5efbbaaa89ebf07f6b4b1b93fc7cbffc"
    ["3.9.0/amd64"]="12c8376c11d684276aeb37770f1efee4b46dda3d9f5f074e301980ba08e529204e2009ab8504ef6a5901594806f6f37a9cb0f5fd4f120d0ba6e727cb407a61b1"
    ["3.9.0/arm64"]="4be5599e56a6bd165e6461d0fd22c7513e295c309a47b71df9eebc661ae76681de4cf5d5363c1aca75f460f2951d30a86aaa6683527f3c461a43a6c4c7be4d8a"
    ["3.8.2/amd64"]="020c254e3b3c054d29c9a522d44540ec6eba1c9dc6fcc6f63aad81d05276f7f60bd217d0aa6c0911f95591d218bf3e4499af1cc1d3412827a24950351badf485"
    ["3.8.2/arm64"]="e7bcb3c61fb27794fb2f3f4d65858cb503e2126c55e64c52d277492a6486629a74986853a9fee38b021192355cd591d777d272072ac2c97a8b2afb1c78cf2d25"
    ["3.8.1/amd64"]="0727b8dbf153ef8f122d1784a37f0a16f53ead81f83b2791d14359c9f0550958ea924675abd0a546844f38b84bf8957695b2e390ed47851622223edab093d93e"
    ["3.8.1/arm64"]="a09c9d6be287d2eb425c89adc4e47919bc65feba0fff6cc1c73c8b619d33808294b6166ddca832f5fa29788824f463cd78dc9270f5b846f9001fa7de806068b5"
    ["3.8.0/amd64"]="f74575d5288ccf59a1883f658215c24c322e57ea96c8a9839638ab6cc3b8a1737b3d95651582830603779f1aefcd828448a16f3f78f139ddce2e85a85c3e1aa3"
    ["3.8.0/arm64"]="6129f60fd09d9b450701bf80a9615d2eec26950aaddbca1748a94de5861a146e4207cd91a3a554c851e3f58cb44a24e00067814b446dd87d066dd6f64da1d892"
    ["3.7.2/amd64"]="acc6e7e7d5b01be4789adb2dc6855e6d224621700a6ebd53ee52c46fe258344771f47b02d8853494d33422b137f84c3645107a085dabe3673202b041bc03c28f"
    ["3.7.2/arm64"]="5f0a18520cb2752d55e1a33c57b5ec42debf4b9ea045654066af7ec98f3061246c5ca9d588bc8269ed77e8dd68ace7cf843056915450f0441d364694cf5c51b7"
    ["3.7.1/amd64"]="108c9945bdc0a79b5315ff29eb6e0ebe968a25f276c5bf91393a555844227efde6cdd4974f115d89fa1992d22c3adde9d20d3773bdafa95a71251bc86fa0e8c6"
    ["3.7.1/arm64"]="71629beaf40ec473a912af302fe3c788a01046a844621ec34f03a2c0b8e70598e3ed58a63a2fe1979e585fcb252198e5ed321804f26f7b80ac5ddcad48f6b011"
    ["3.7.0/amd64"]="96fd1be305ad7103e94286d9fbb84da89972cea548152c623a90b56b76a5237160e834725b82ef7cdd6d0f71ae7965b9ded1e1ca28e4e37c0c5d76c6879221eb"
    ["3.7.0/arm64"]="ccaefca7fda7a22c81263fb46f958f66b4d5a01ddf3a8728356662976a4b0d43320cfcd65640388aac7b293f1852a1c233f8064c3a24917962a2c1ace68ca44e"
    ["3.6.3/amd64"]="0354b1feb970b7a97a4e57dd6bb227a5009c045ff77519e9e85963f6108e9107b488f3b401fb456c80f9675002a2070bb793ff866da4b4611086466148b6963a"
    ["3.6.3/arm64"]="e1567892b50e439e33bf6c055253b08bd39d11cc7b4994226f74cae2465ad46c2d97764b13bff324074912bdc217867748b368075e144b7b4b5b8329f6ef4e63"
    ["3.6.2/amd64"]="6a16ff92c7969a5f0a6d4a53ba0eaa081f631052f9fec84087550fa8ad1322b76b0961e1e0cccb54b5209672fe8eecdbf9064b7f33f20b8ca57eddc3e5ec16fb"
    ["3.6.2/arm64"]="a3840f4ddb9a416bb44b335167a99b65eb589fd73acb1aed7d68659ca70972d9da0e59fc0d1f12975189f61ae2fa95af38f6cb570d6ad7dd0aafbdd41f139a96"
    ["3.6.1/amd64"]="55ef0c98a1c07f42f3dd3899a4e1fc93d68453b0ad8fce9fd25f560dc09d8cfec2e5114f78c5daa921ee0415c4aecb5fed7f61fe6aa0622ce2cb413911481b4a"
    ["3.6.1/arm64"]="6c41154936b30b87113b6dd3cc5c2f60d5afa8a61e07810b27ac1eac3e60a86cf3b237779f6a94171cd568f8f3a3c743d36c28b3877759413099ada47bf2286c"
    ["3.6.0/amd64"]="b452c0071cd8dc4a796683d5b80fd57b1febcabe784fad2ff4c672809d3cc61c73f5bd46187008b234f1e383e94631ddebd13d3c547f3dea475453f68adb405c"
    ["3.6.0/arm64"]="920f40b7779c79ddbb0578f361b80e399e4a82e483649aa9e2de2794cda43b4540e30d639f4d5e0463bbad9a102fbc151d7530426ef47851b4daec6affe620f0"
    ["3.5.4/amd64"]="a7aa2810507b012a1696e02f3bbb615cf09cc574cb27937197a3b860192069ad1659f504a51282ff6a93121dc932f77e4d96e6efa44525c2ba1b7b7d21aabb8b"
    ["3.5.4/arm64"]="67954a3f4faa1516582134fbe9cedef5b1b2f5c5160681e3b9b6dea65af14d25cc58883e63d1acd4be79a8911396c7839dbf73b4ab95dae4a009b4c1491f256f"
    ["3.5.3/amd64"]="1727b74fc1ec04476ee2068440faf019b858cd3f6956595137d42d35d42825cae2b3d0de0cb61ca625ed0371885ecbdc5571cfcdc029f454c395fa561932f929"
    ["3.5.3/arm64"]="46d55a6500422db3d17c8a5ced2902abc0d8604bbc1f1fb3bcca35fbdd4e641e2f099d76c7c5a6ad4ddb0c4958ff7d4c271b6075eff4e85fe7690b34b2b7f9c8"
    ["3.5.2/amd64"]="e3aa1d2b8979ad69eee3e1c740b97729cb4a5857a667c16679d179426f6f967ef1d742a59217437650a422e2694d32653f32c76a85a1fb471d3980bf22d19f4f"
    ["3.5.2/arm64"]="08d1cb6f67bdcf0fe2ef735104874b488cee4b0647da40013a6c9f50ffedc88f77f3e5a1758321733717e9523d00afae6d801751d5b58352875b6d13e0e75f16"
    ["3.5.1/amd64"]="e3c2f536abe5632852243bc4f3f8d31ea3db673b40c8dfd8ad610881b2270d5dc497c676dec7e9b0e0fd797e89e057356e3a447cc8ae1d2ac8e8d31afb079e00"
    ["3.5.1/arm64"]="4cb387d5adc61d89f8a5fbd9143b244ca8b64e80c1c42eb79a441a40d147551a598ce815e3a95089cc81afb68fc1ba3dcf276c3187d0229b74880a4619590b7c"
    ["3.5.0/amd64"]="c5a0abbd34bd65ffbf321f17393ccfbbb76d1c2d106bfcb738f711c2061293e937f56781c65443d91f9a63b48ffa9b73a199e5bf36f2ffe72df2bb2e3d20c788"
    ["3.5.0/arm64"]="9b90145a10f0458b6fd665954a6155aba74d529fe7cf9e0703678920067d77629f05fb893a44ff5a334f3ba897f4b427b0baa089dfca60877ce497de91b8835d"
    ["3.4.2/amd64"]="d89093f1c463355b7280017c357a7d86825548a96d6b6772ae07fcc76a25474d02d3ba8f125514c49ff83383410863cd8b56702c5f9dcfa1f3f0d23ac1587fa1"
    ["3.4.2/arm64"]="123dfba52f048e1c56efb681e45b430c6dda9db4d027061bc0f34da424f61a284026290a5365e4374fa580f25219c13647581bf0544a0a8e3b166f41796ff898"
    ["3.4.1/amd64"]="dba79d7081858331d28655b15280d4b6575b120e82486d869c70ab6d662ddaa29e02fe0fa38f3a57e908e8b0be9e210247cb06cba36800c9689c63c4087e16d8"
    ["3.4.1/arm64"]="315dfb302f897179fc3c2f905c304fff5303745e38c3ade344f7fda336532e30fc7fb60e4edc3e4b31f932b56a97a42586dd2692d614dd3443ebb85f0ff22926"
    ["3.4.0/amd64"]="c8f5269553177dc5f310dc2c462bbab91edd38d8c11b35f7ab798dc3315606606edb5763f2df46ea39b919e54be4be85953c933a4adb5fc72ca214b918bc3bf1"
    ["3.4.0/arm64"]="9d411ec6680c192d31f2da3213b26e556265b43b6762d78e094c535063cbaf8dd560b7cd13b04fe3a4a80db47edfb8dfcdf57f8192ffff4747bf09fd084ec76d"
    ["3.3.4/amd64"]="2f5db203a6bdaa8ce4cdf075db0b981458359fe73f8c523c96d5cb16cfbf803ce53d08b5fda8bcb30f62ffa4836fb860b7cfc02244ce7d0ec463cb19dfbc80c3"
    ["3.3.4/arm64"]="43ec71d133823cda9ae5af5188fb1a4c814364b6887e8195202bc558a979906e83b6af184f2da2876c5d73d2230fb170befc19cf7c52f7b7507cfaff7d5001e1"
    ["3.3.3/amd64"]="516f0b9b98d0f72df3e702bb8cdd852c2ce807ae915f6d78469a4eed88829aa13be9a87e6c6bbd2514d28cbb4fc182c27d2d5d78766e5f901db39e2492685b48"
    ["3.3.3/arm64"]="d5c7b313a5deeb76e9a60c1fb178344b0aa4131d8bba535f25f7f6ceb0052ed04dd0b61f318633a01eb52c6e06253bc03c699ae58fa5ec0284673b0e6f2d81da"
    ["3.3.2/amd64"]="f0364818a6b3fdeeb75027572c87702e67fa8190571559968cead2af53d0e4bd40e7d8764824de98ffc4e7749bf19b9cd2987a70cd5f8a4d3a2bd8e15fba136b"
    ["3.3.2/arm64"]="36229dbffe7db217eb674a09db22b1ea6419f3b60bc23be26570e14915894e1eecfdb9dff723cfa29c0ac6b9bdf6816593e376fcbe5d2c532d3bea392a5a30a9"
    ["3.3.1/amd64"]="c3028af61303aeacdc31a12846be608b5115edb2e49543736647534b92d8a310df70e390b0c0f05e65ca23f9ca48f816c431d21b6d04dbd54185a9aee8d1106c"
    ["3.3.1/arm64"]="2d7efb490c29356e8c86b178784fd05531bf12fe140e82b767643a6102e7705ea795d01b0d4345e8a2e98268f04c6beef397b2e36e85330cab90b8d7e52ce5c7"
    ["3.3.0/amd64"]="7bd61e82bf94505049e3a227a20c19b4a5a202740cc53da4bcf1615b8be76e516e090a73d5dbd64df39b413228df598d9018c3ecaf3cf5511dde2ceb064fc6f1"
    ["3.3.0/arm64"]="6ad9d70cff6c14dd21335103df53b7db062501c7491f4c694fa982a955d52c29571d31b8211123a3519332ec74fb41c5ed53061ef2f5c1ab6c5ae0a4d41ce5fd"
    ["3.2.4/amd64"]="a578cf6600f740e497414a0c842d805cade34b0fd0bedd527bfa291e033f65c91ccbb707fec447c8e40a174a477efe2f4c2d0f7c265b70cdc2203d5f72b32695"
    ["3.2.4/arm64"]="92ac36aff5c9bbb5cb051cf934880402d0cc93d66da3f8d5accad070c8975e66004ea68ab4bcf606d1393c7d2d2cc233a1d6eba9a563671048d041b22e81950b"
    ["3.2.3/amd64"]="37c27c394d547de988453b0099683b0f3ce7da0bc4fa55306cac2f760caf443287a941dc5e8592fb8f1aceedbc0ab063f5de3301f791e91580f0d704311be165"
    ["3.2.3/arm64"]="63bf293fd8a750532832811c73b3043c096db21f564e0f8158282a23c42c9dd2946ae48f1e0a9a71c69f1812bcab29913c68168fb57086bf22feedb4d7850064"
    ["3.2.2/amd64"]="45573dfb90c757e2d93dff4a892936dab834a545e33aef194ec60236c70fe713c7db195fa685b2c4396e2d8b5a0e67de5e9b3b237b0bbc372b873b954a185d73"
    ["3.2.2/arm64"]="d2ce36b9e85b6050eae17c6d36a4d11d583ce96ebe40bfe69770f7ed4589b7391ec8dee0e94c61440fc35e98071d7ebf7b3ed789dfff8c8ab213c3872fb729a3"
    ["3.2.1/amd64"]="e4de25ca4720236ef2bb50be6ed57ec9779526e09cae4e9da5c0173c964c46475e8b4276bef91ccf3eb23f0d0edf8cd314d87c19bcb0099731d7984e1e9cdcc4"
    ["3.2.1/arm64"]="38de1e2c7138087633fc64f373594ec479df6f6082285e5e10e2259d4a8344561be8450b3ded9fc468c467f269012191fd8349ef0867ff4021724df2809ea220"
    ["3.2.0/amd64"]="8e8da609f50757e542a1449b00f1a53e53653c961e0db6a3ac4f1caabc5653f2e0ad77a96553e0c6a670fe0a28c6b7ae2b7af78fb1af9a9632c10b6e17a07a2a"
    ["3.2.0/arm64"]="86966a455f61418e3d0b309fd74cfd47c968735d72707adb78827b922422eeea79030988f58abcb13b5b878b7dd85ebaf17f52fb0370d0afdc224c10d9e82999"
    ["3.1.3/amd64"]="12ceb64adc95ba8066440b4214a2b2413355681cc5ad3090dcd27039bdebc3a9c0f8bdc615d52f2702f2eafd0cc34656316d5c1b0e9bec0e1a45ce688dbd6390"
    ["3.1.3/arm64"]="d3420b50f233fcafbdaf2f2c1af89f13cd80c34729cb7a434dac60cf4541931cc5470381165fd43ed3f768664e7a5349bf9eaa1770bc55da0dec6d6d43d626d2"
    ["3.1.2/amd64"]="97b84740ca89732e2a3e610912c1e2a1d022c2470164562fc8094dfcf3163530f99e7a7353e8a638e7d9d3a36bf92578752cd6b2a106eefd9110d30ed464fc72"
    ["3.1.2/arm64"]="80e6bcbe8ce2cba1027debcc1ea48336741a278041836880f5cd0d2da21e69d28a6b423e74fba7128987d6e3bed23d7b830a588034f1c1dc443c3693582340b9"
    ["3.1.1/amd64"]="28523da84731d8d80777673b351c4baea0a33f816846d67d783496cc3eeee990ba0362cf4db822e886a9baa66a98b87cb5a24622eafefbb0334b5f64eaaa9282"
    ["3.1.1/arm64"]="b63a6373faf3a665fefefcbc72a02f551b0aa7533c8e753e3e749a85ae8014fbbf9e69ca4965ceea8e830612309d9dd9b8e3bffd542ba88a120affe43ea15020"
    ["3.1.0/amd64"]="b36697314fafc5f5cb090d87feba98d5cc4b8e08ffb0f375a15b8799f602f0e986428687655ac4b8d758d584e5d1aca03005d6deb9e3d9c691c4751da9af8d5e"
    ["3.1.0/arm64"]="d58f0ebb7b2481ce80b48e699d7bc2b5ed432e8a25772fb1061ef7424decebe55f4a463c7627a70b30149896b7f15039294b635f563a2a148062b9335cc305c3"
    ["3.0.3/amd64"]="fdfaec2192f2e4d401c67e10330186ee8f803264fb75ced01ba86c9f4190615191b6c3e03b8c6a1bd034671cafe7b155a767f13c106f46a0a653c9d7079e65e4"
    ["3.0.3/arm64"]="cd33e9da0880f6858a7d3143aabcf525c8714193707f21736b1e5dabb133436652fd09acff71064393703cb1b786a80d68bf59db744221d0244a221416c3d18d"
    ["3.0.2/amd64"]="529bc0c9875db208e3b7eac67e66e7b73af8861e61f3bb1bfe4aa947089d00dfa4278fdd391da8a825e38cccbcb0960835022978a0fd55027a590662ae58f57e"
    ["3.0.2/arm64"]="66a9f5f740791367e8d1d6f0ab7df056614637f5b2a313f54fe6a06ac23598c7f5d0d465a774570986741453c07da2e88db2720fc0441d553d9e4104d0a23018"
    ["3.0.1/amd64"]="a16cd36cf07be054bf8bad29dbe91f46e0fc1056c9adec51b47453c7fd063da1d8792ab1d0eef00c8cd94446c0f6c5de6052ae0acc3df905f015e069edd322d7"
    ["3.0.1/arm64"]="673fd1b2f99d2ae21a335f69766e03f7398bf5a7f84837499b606e76890469c2b39f468aa7aa506b5f87766fe00ccf25e402f41d6986581094b61805de005c7e"
    ["3.0.0/amd64"]="849568bbd075c9dc30812bf8ccc5a42c35917ac98b1a82d2909558b6c81e8c64c5293a856ee19a9c3eaf3be6a5309e42294f5e549b4a228508c7c747908fb7c4"
    ["3.0.0/arm64"]="53b9aead93791936667a3e1d3bc542df5394ef7438a98b2528a42096b072dbe96627cdbaf9a75021c0f7b8b5e732b8e852c16a902c056d87af4c5e59d8552466"
)
# <<< checksum table <<<

orb_install_main
