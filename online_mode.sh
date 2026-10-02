#!/bin/bash
#==============================================================================
# online_mode.sh
#
# Online counterpart of install_camera.sh. install_camera.sh execs into this
# script (and never returns) when the machine has network. Here the camera
# driver is NOT taken only from the bundled vendors/ tree - it is picked from
# up to THREE parallel sources, each independently probed and skipped if
# unreachable (never a hard failure unless all three are empty):
#
#   github - live-fetched from
#            https://github.com/advantech-edge-ai/camera-driver/raw/refs/heads/main/internet_list.sh
#            (falls back to the bundled internet_list.sh if the fetch fails)
#   gitlab - internal_list.sh (the company internal file server / GitLab file
#            host at 172.17.4.45:6001)
#   local  - the bundled vendors/ tree already on disk, scanned live, no
#            download needed
#
# All keys follow the GitHub internet_list.sh format:
#   <vendor>/<sensor>/<platform>/<board>/<jetpack>
#   platform = orin_nx_orin_nano | agx_orin | thor
#   board    = the real product the driver was built for (mic_741, mic_743,
#              mic_742, mic_733ao, ...) - boards are NOT folded together.
#
# The Vendor -> Sensor menu is the UNION of all three sources and tags each
# item with the source(s) it was found in, e.g. "(github,gitlab,local)".
# After a sensor is picked the operator picks one board/JetPack variant.
# The machine is NOT checked at start-up; only once a package is selected is
# it compared against the device (/opt/version model + JetPack, TEGRA_CHIPID):
# wrong SoC family -> refused; different board / JetPack / unreadable
# /opt/version -> Yes/No warning. If more than one source carries the chosen
# driver, a second menu lets the operator pick which source to install from.
#
# Downloaded/extracted packages land in
#   vendors/<vendor>/<sensor>/<platform>/<board>/<jetpack>/
# (the same layout a bundled driver would have; key platform "thor" is stored
# on disk as "agx_thor" like the rest of vendors/); a "local" pick installs
# straight from the existing bundled leaf, no download/copy.
#
# Usage: sudo bash online_mode.sh          (normally reached via install_camera.sh)
#==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDORS_DIR="${SCRIPT_DIR}/vendors"
CACHE_DIR="${CF_CACHE_DIR:-/opt/advantech/camera_framework/download}"
LOG_DIR="${SCRIPT_DIR}/logs"
VERSION_FILE="${CF_VERSION_FILE:-/opt/version}"
NV_BOOT_CONF="${CF_NV_BOOT_CONF:-/etc/nv_boot_control.conf}"
GITHUB_LIST_RAW_URL="https://github.com/advantech-edge-ai/camera-driver/raw/refs/heads/main/internet_list.sh"

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/online_mode_$(date +%Y%m%d_%H%M%S).log"

log()  { echo "[INFO] $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[WARN] $*" | tee -a "${LOG_FILE}" >&2; }
err()  { echo "[ERR ] $*" | tee -a "${LOG_FILE}" >&2; }
die()  { err "$*"; exit 1; }

require_root() { [[ "${EUID}" -eq 0 ]] || die "Please run with sudo or as root."; }

# ---------------------------------------------------------------------------
# key helpers  (key = <vendor>/<sensor>/<platform>/<board>/<jetpack>,
#               GitHub internet_list.sh format)
# ---------------------------------------------------------------------------
key_vendor()   { cut -d/ -f1 <<< "$1"; }
key_sensor()   { cut -d/ -f2 <<< "$1"; }
key_platform() { cut -d/ -f3 <<< "$1"; }
key_board()    { cut -d/ -f4 <<< "$1"; }
key_jetpack()  { cut -d/ -f5 <<< "$1"; }

# key platform <-> vendors/ directory name (GitHub says "thor", the bundled
# tree says "agx_thor"; every other platform is spelled the same)
platform_to_dir() { [[ "$1" == "thor" ]] && echo "agx_thor" || echo "$1"; }
dir_to_platform() { [[ "$1" == "agx_thor" ]] && echo "thor" || echo "$1"; }

# vendors with no <sensor> level in the bundled tree - a synthetic sensor
# token (GitHub's spelling) keeps the 5-segment key shape across sources.
declare -gA LOCAL_SYNTH_SENSOR=( ["realsense"]="D457" )

# ---------------------------------------------------------------------------
# device check - run only once a package has been selected
#   return 0 = go on, 1 = operator declined, 2 = refused (wrong SoC family)
# ---------------------------------------------------------------------------
check_device_for_key() {
    local key="$1"
    local raw="" model="" board="" jp="" chip="" dev_family="" pkg_family f
    local -a parts=() problems=()

    if [[ -r "${VERSION_FILE}" ]]; then
        raw="$(head -n1 "${VERSION_FILE}")" ; raw="${raw//$'\r'/}"
        IFS='_' read -r -a parts <<< "${raw%%,*}"
        model="${parts[0]:-}"
        board="${model,,}" ; board="${board//-/_}"
        for f in "${parts[@]:1}"; do [[ "${f}" =~ ^[0-9]+\.[0-9]+$ ]] && { jp="jp${f}"; break; }; done
    fi
    chip="$(awk '/TEGRA_CHIPID/{print $2; exit}' "${NV_BOOT_CONF}" 2>/dev/null || true)"
    case "${chip}" in 0x26) dev_family="thor" ;; 0x23) dev_family="orin" ;; esac
    case "$(key_platform "${key}")" in thor) pkg_family="thor" ;; *) pkg_family="orin" ;; esac

    log "Device : ${raw:-<${VERSION_FILE} not readable>}  (TEGRA_CHIPID ${chip:-unknown})"

    if [[ -n "${dev_family}" && "${dev_family}" != "${pkg_family}" ]]; then
        err "Selected driver is for $(key_platform "${key}") but this device is ${dev_family} (TEGRA_CHIPID ${chip}) - refusing."
        return 2
    fi
    [[ -n "${dev_family}" ]] || problems+=("SoC family unknown (no TEGRA_CHIPID in ${NV_BOOT_CONF})")
    if [[ -z "${board}" ]]; then
        problems+=("product model unknown (${VERSION_FILE} not readable)")
    elif [[ "${board}" != "$(key_board "${key}")" ]]; then
        problems+=("board   : device ${model} (${board})  vs  driver $(key_board "${key}")")
    fi
    if [[ -z "${jp}" ]]; then
        problems+=("JetPack unknown (not found in ${VERSION_FILE})")
    elif [[ "${jp}" != "$(key_jetpack "${key}")" ]]; then
        problems+=("JetPack : device ${jp}  vs  driver $(key_jetpack "${key}")")
    fi

    if [[ "${#problems[@]}" -eq 0 ]]; then
        log "Device matches the selected driver (${board} / ${jp} / ${dev_family})."
        return 0
    fi

    local p yn
    {
        echo
        echo "!! Device / driver mismatch warning !!"
        echo "  Selected driver : ${key}"
        for p in "${problems[@]}"; do echo "  - ${p}"; done
        echo "  Installing a driver built for a different product model / JetPack may"
        echo "  leave the device unable to boot or with the camera non-functional."
        echo
    } >&2
    read -r -p "Install this driver anyway? [y/N]: " yn
    case "${yn:-N}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

url_reachable() { wget -q --spider --timeout=8 --tries=1 "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# three-source collection - each is independently probed / scanned and
# skipped (never fatal) if unavailable
# ---------------------------------------------------------------------------
declare -gA CAT_GITHUB   # key -> download URL
declare -gA CAT_GITLAB   # key -> download URL
declare -gA CAT_LOCAL    # key -> 1  (already present under vendors/)

# live-fetch internet_list.sh from GitHub; falls back to the bundled static
# copy (already sourced by the caller) if the fetch fails or looks bad.
fetch_github_list() {
    local tmp="${CACHE_DIR}/internet_list.sh.remote"
    mkdir -p "${CACHE_DIR}"
    if wget -q --timeout=10 --tries=2 -O "${tmp}" "${GITHUB_LIST_RAW_URL}" \
        && [[ -s "${tmp}" ]] \
        && grep -q 'declare -gA INTERNET_LIST' "${tmp}"; then
        # shellcheck disable=SC1090
        source "${tmp}"
        log "Fetched live internet_list.sh from GitHub (${#INTERNET_LIST[@]} entries)."
        return 0
    fi
    warn "Could not fetch live internet_list.sh from GitHub; using the bundled copy."
    return 1
}

collect_github() {
    [[ -f "${SCRIPT_DIR}/internet_list.sh" ]] && source "${SCRIPT_DIR}/internet_list.sh"
    if [[ -z "${INTERNET_PROBE:-}" ]]; then
        warn "internet_list.sh has no INTERNET_PROBE; skipping github source."
        return 0
    fi
    log "Checking GitHub ... ${INTERNET_PROBE}"
    if ! url_reachable "${INTERNET_PROBE}"; then
        warn "GitHub not reachable; skipping github source."
        return 0
    fi
    fetch_github_list || true   # on failure INTERNET_LIST keeps the bundled content already sourced above
    local k
    for k in "${!INTERNET_LIST[@]}"; do CAT_GITHUB["${k}"]="${INTERNET_LIST[$k]}"; done
    log "github source available: ${#INTERNET_LIST[@]} entries."
}

collect_gitlab() {
    [[ -f "${SCRIPT_DIR}/internal_list.sh" ]] && source "${SCRIPT_DIR}/internal_list.sh"
    if [[ -z "${INTERNAL_PROBE:-}" ]]; then
        warn "internal_list.sh has no INTERNAL_PROBE; skipping gitlab source."
        return 0
    fi
    log "Checking internal server (gitlab) ... ${INTERNAL_PROBE%%/space/*}"
    if ! url_reachable "${INTERNAL_PROBE}"; then
        warn "Internal server (gitlab) not reachable; skipping gitlab source."
        return 0
    fi
    local k
    for k in "${!INTERNAL_LIST[@]}"; do CAT_GITLAB["${k}"]="${INTERNAL_LIST[$k]}"; done
    log "gitlab source available: ${#INTERNAL_LIST[@]} entries."
}

collect_local() {
    if [[ ! -d "${VENDORS_DIR}" ]]; then
        warn "No bundled vendors/ tree at ${VENDORS_DIR}; skipping local source."
        return 0
    fi
    local f rel key
    local -a t
    while IFS= read -r f; do
        rel="${f#"${VENDORS_DIR}"/}"
        rel="${rel%/install.sh}"
        IFS='/' read -r -a t <<< "${rel}"
        if [[ "${#t[@]}" -eq 5 ]]; then
            key="${t[0]}/${t[1]}/$(dir_to_platform "${t[2]}")/${t[3]}/${t[4]}"
        elif [[ "${#t[@]}" -eq 4 ]]; then
            key="${t[0]}/${LOCAL_SYNTH_SENSOR[${t[0]}]:-unknown}/$(dir_to_platform "${t[1]}")/${t[2]}/${t[3]}"
        else
            warn "Skipping unexpected local leaf depth: ${rel}"
            continue
        fi
        CAT_LOCAL["${key}"]=1
    done < <(find "${VENDORS_DIR}" -mindepth 1 -type f -name install.sh 2>/dev/null)
    log "local source available: ${#CAT_LOCAL[@]} entries."
}

all_keys() {
    {
        (( ${#CAT_GITHUB[@]} )) && printf '%s\n' "${!CAT_GITHUB[@]}"
        (( ${#CAT_GITLAB[@]} )) && printf '%s\n' "${!CAT_GITLAB[@]}"
        (( ${#CAT_LOCAL[@]}  )) && printf '%s\n' "${!CAT_LOCAL[@]}"
        true
    } | sort -u
}

sources_for() {
    local key="$1"
    local -a out=()
    [[ -n "${CAT_GITHUB[$key]:-}" ]] && out+=("github")
    [[ -n "${CAT_GITLAB[$key]:-}" ]] && out+=("gitlab")
    [[ -n "${CAT_LOCAL[$key]:-}"  ]] && out+=("local")
    local IFS=','
    echo "${out[*]}"
}

# ---------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------
show_menu() {
    local title="$1" ; shift ; local items=("$@") choice
    { echo ; echo "========================================"
      echo " ${title}"
      echo "========================================"
      local i=1 ; for it in "${items[@]}"; do echo "${i}. ${it}" ; ((i++)) ; done
      echo "0. Back/Exit" ; echo ; } >&2
    while true; do
        read -r -p "Please select [0-${#items[@]}]: " choice || return 1   # EOF -> Back/Exit
        [[ "${choice}" =~ ^[0-9]+$ ]] || { echo "  enter a number" >&2 ; continue ; }
        [[ "${choice}" -eq 0 ]] && return 1
        (( choice >= 1 && choice <= ${#items[@]} )) && { printf '%s\n' "${items[$((choice-1))]}" ; return 0 ; }
        echo "  out of range" >&2
    done
}

# dest dir for a driver - identical to the bundled vendors/ layout.
# realsense has no <sensor> level in the framework, so strip it there.
dest_dir_for() {
    local vendor="$1" sensor="$2" platform board="$4" jetpack="$5"
    platform="$(platform_to_dir "$3")"
    if [[ "${vendor}" == "realsense" ]]; then
        printf '%s\n' "${VENDORS_DIR}/${vendor}/${platform}/${board}/${jetpack}"
    else
        printf '%s\n' "${VENDORS_DIR}/${vendor}/${sensor}/${platform}/${board}/${jetpack}"
    fi
}

# ---------------------------------------------------------------------------
# narrow a (vendor, sensor) menu pick down to one specific package key
#   return 0 = TARGET_KEY set, 1 = nothing found, 2 = operator backed out
# ---------------------------------------------------------------------------
TARGET_KEY=""

pick_package() {
    local vendor="$1" sensor="$2"
    TARGET_KEY=""

    local -a variants
    mapfile -t variants < <(all_keys | awk -F/ -v v="${vendor}" -v s="${sensor}" '$1==v && $2==s')

    [[ "${#variants[@]}" -gt 0 ]] || return 1
    if [[ "${#variants[@]}" -eq 1 ]]; then
        TARGET_KEY="${variants[0]}"
        return 0
    fi

    local -a labels=()
    local v
    for v in "${variants[@]}"; do
        labels+=("$(key_platform "${v}")/$(key_board "${v}")/$(key_jetpack "${v}")  ($(sources_for "${v}"))")
    done
    local chosen
    chosen="$(show_menu "Select package for [${vendor}/${sensor}]" "${labels[@]}")" || return 2
    local idx
    for idx in "${!labels[@]}"; do
        [[ "${labels[$idx]}" == "${chosen}" ]] && { TARGET_KEY="${variants[$idx]}"; break; }
    done
    return 0
}

select_source() {
    local key="$1"
    local -a avail=()
    [[ -n "${CAT_GITHUB[$key]:-}" ]] && avail+=("github")
    [[ -n "${CAT_GITLAB[$key]:-}" ]] && avail+=("gitlab")
    [[ -n "${CAT_LOCAL[$key]:-}"  ]] && avail+=("local")

    if [[ "${#avail[@]}" -eq 1 ]]; then
        log "Only ${avail[0]} carries this driver - auto-selected."
        printf '%s\n' "${avail[0]}"
        return 0
    fi
    show_menu "Select download source for [${key}]" "${avail[@]}"
}

# ---------------------------------------------------------------------------
# download + verify + unpack into the vendors/ tree, then install
# (used for the github / gitlab sources; "local" installs in place instead)
# ---------------------------------------------------------------------------
download_and_install() {
    local url="$1" dest="$2"
    local asset="${url##*/}" ; local cache="${CACHE_DIR}/${asset}"
    mkdir -p "${CACHE_DIR}"

    log "Driver package : ${url}"
    wget --no-verbose --timeout=60 --tries=3 -O "${cache}" "${url}" \
        || { err "Download failed: ${url}" ; rm -f "${cache}" ; return 1 ; }

    # integrity (GitHub always ships <asset>.md5sum; internal often does too)
    local want got
    want="$(wget -qO- "${url}.md5sum" 2>/dev/null | awk '{print tolower($1); exit}')"
    if [[ -n "${want}" ]]; then
        got="$(md5sum "${cache}" | awk '{print tolower($1)}')"
        [[ "${got}" == "${want}" ]] || { err "MD5 mismatch (${got} != ${want})" ; rm -f "${cache}" ; return 1 ; }
        log "MD5 verified."
    else
        warn "No .md5sum published for ${asset}; skipping integrity check."
    fi

    local stage ; stage="$(mktemp -d)"
    case "${asset}" in
        *.tbz2|*.tar.bz2|*.tbz) tar -xjf "${cache}" -C "${stage}" ;;
        *.tar.gz|*.tgz)         tar -xzf "${cache}" -C "${stage}" ;;
        *.tar.xz|*.txz)         tar -xJf "${cache}" -C "${stage}" ;;
        *.zip)                  unzip -q "${cache}" -d "${stage}" ;;
        *) err "Unsupported archive type: ${asset}" ; rm -rf "${stage}" ; return 1 ;;
    esac || { err "Failed to extract ${asset}" ; rm -rf "${stage}" ; return 1 ; }

    # locate the real package dir (installers ship at varying nesting depth)
    local entry pkg
    entry="$(find "${stage}" -maxdepth 5 -type f -name install.sh | head -n1)"
    [[ -z "${entry}" ]] && entry="$(find "${stage}" -maxdepth 5 -type f -name install_binaries.sh | head -n1)"
    [[ -n "${entry}" ]] || { err "No install.sh / install_binaries.sh inside ${asset}" ; rm -rf "${stage}" ; return 1 ; }
    pkg="$(dirname "${entry}")"

    log "Installing into : ${dest}"
    rm -rf "${dest}" ; mkdir -p "${dest}"
    cp -a "${pkg}/." "${dest}/"
    rm -rf "${stage}"

    chmod +x "${dest}"/*.sh 2>/dev/null || true
    (
        cd "${dest}"
        if [[ -f install.sh ]]; then bash ./install.sh
        else bash ./install_binaries.sh
        fi
    ) 2>&1 | tee -a "${LOG_FILE}"
}

# install straight from the already-present bundled vendors/ leaf - no
# download, no copy.
install_from_local() {
    local key="$1"
    local dest
    dest="$(dest_dir_for "$(key_vendor "${key}")" "$(key_sensor "${key}")" "$(key_platform "${key}")" "$(key_board "${key}")" "$(key_jetpack "${key}")")"
    [[ -d "${dest}" ]] || { err "Local path not found: ${dest}" ; return 1 ; }
    [[ -f "${dest}/install.sh" ]] || { err "install.sh not found: ${dest}/install.sh" ; return 1 ; }
    log "Installing from local bundled package: ${dest}"
    (
        cd "${dest}"
        bash ./install.sh
    ) 2>&1 | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
main() {
    require_root
    log "Online camera installer started (multi-source: github/gitlab/local)."

    collect_github
    collect_gitlab
    collect_local

    local total ; total="$(all_keys | wc -l)"
    [[ "${total}" -gt 0 ]] || die "No camera drivers available from any source (github/gitlab/local)."

    while true; do
        local vendor
        mapfile -t vendors < <(all_keys | cut -d/ -f1 | sort -u)
        vendor="$(show_menu "Select Vendor" "${vendors[@]}")" \
            || { log "User exited." ; exit 0 ; }

        while true; do
            mapfile -t sensors < <(all_keys | awk -F/ -v v="${vendor}" '$1==v{print $2}' | sort -u)

            local -a labels=() sensor_of_label=()
            local s
            for s in "${sensors[@]}"; do
                local -a vkeys
                mapfile -t vkeys < <(all_keys | awk -F/ -v v="${vendor}" -v s="${s}" '$1==v && $2==s')
                local -A seen=()
                local vk src o tag=""
                for vk in "${vkeys[@]}"; do
                    for src in $(sources_for "${vk}" | tr ',' ' '); do seen["${src}"]=1; done
                done
                for o in github gitlab local; do
                    [[ -n "${seen[$o]:-}" ]] && tag+="${tag:+,}${o}"
                done
                labels+=("${s}  (${tag})")
                sensor_of_label+=("${s}")
            done

            local chosen_label
            chosen_label="$(show_menu "Select Sensor under [${vendor}]" "${labels[@]}")" || break

            local sensor="" idx
            for idx in "${!labels[@]}"; do
                [[ "${labels[$idx]}" == "${chosen_label}" ]] && { sensor="${sensor_of_label[$idx]}"; break; }
            done

            local rc=0
            pick_package "${vendor}" "${sensor}" || rc=$?
            if [[ "${rc}" -ne 0 ]]; then
                [[ "${rc}" -eq 1 ]] && warn "No installable driver found for ${vendor}/${sensor}."
                continue
            fi

            rc=0
            check_device_for_key "${TARGET_KEY}" || rc=$?
            if [[ "${rc}" -ne 0 ]]; then
                [[ "${rc}" -eq 1 ]] && log "User declined install on a mismatched device."
                continue
            fi

            local source
            source="$(select_source "${TARGET_KEY}")" || { warn "No source selected." ; continue ; }

            local dest
            dest="$(dest_dir_for "$(key_vendor "${TARGET_KEY}")" "$(key_sensor "${TARGET_KEY}")" "$(key_platform "${TARGET_KEY}")" "$(key_board "${TARGET_KEY}")" "$(key_jetpack "${TARGET_KEY}")")"

            {
                echo
                echo "You selected : ${vendor} / ${sensor}"
                echo "Target       : $(key_platform "${TARGET_KEY}")/$(key_board "${TARGET_KEY}")/$(key_jetpack "${TARGET_KEY}")"
                echo "Source       : ${source}"
                echo "Install dir  : ${dest}"
                echo
            } >&2
            local yn ; read -r -p "Download and install now? [y/N]: " yn
            case "${yn:-N}" in y|Y|yes|YES) ;; *) continue ;; esac

            local ok=1
            case "${source}" in
                github) if download_and_install "${CAT_GITHUB[${TARGET_KEY}]}" "${dest}"; then ok=0; fi ;;
                gitlab) if download_and_install "${CAT_GITLAB[${TARGET_KEY}]}" "${dest}"; then ok=0; fi ;;
                local)  if install_from_local "${TARGET_KEY}"; then ok=0; fi ;;
            esac

            if [[ "${ok}" -eq 0 ]]; then
                echo
                echo "Installation finished.  Log: ${LOG_FILE}"
                echo "The system may reboot automatically if the vendor installer triggered it."
                echo "After reboot, run  init.sh  then  cam.sh <N>  from:"
                echo "  ${dest}"
                exit 0
            fi
            warn "Installation did not complete; back to the menu."
        done
    done
}

main "$@"
