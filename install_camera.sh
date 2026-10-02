#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDORS_DIR="${SCRIPT_DIR}/vendors"
LOG_DIR="${SCRIPT_DIR}/logs"

mkdir -p "${LOG_DIR}"
find "${LOG_DIR}" -maxdepth 1 -type f -name 'install_camera_*.log' -print -delete | while read -r oldlog; do
    echo "[INFO] Deleted old log: ${oldlog}"
done
LOG_FILE="${LOG_DIR}/install_camera_$(date +%Y%m%d_%H%M%S).log"
VERSION_FILE="/opt/version"

DETECTED_BOARD=""
DETECTED_JETPACK=""
SYSTEM_VERSION_RAW=""
DETECTED_PLATFORM=""
PACKAGE_BOARD=""

# -----------------------------
# Basic logging
# -----------------------------
log() {
    echo "[INFO] $*" | tee -a "${LOG_FILE}"
}

warn() {
    echo "[WARN] $*" | tee -a "${LOG_FILE}" >&2
}

err() {
    echo "[ERR ] $*" | tee -a "${LOG_FILE}" >&2
}

die() {
    err "$*"
    exit 1
}

# -----------------------------
# Helpers
# -----------------------------
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Please run this script with sudo or as root."
    fi
}

# True when the machine can reach an online driver source (internal server or
# GitHub). When it can, main() hands over to online_mode.sh and never returns.
online_reachable() {
    local u
    for u in "http://172.17.4.45:6001" "https://github.com"; do
        wget -q --spider --timeout=5 --tries=1 "${u}" 2>/dev/null && return 0
    done
    return 1
}

#pause_enter() {
#    read -r -p "Press Enter to continue..." _
#}

# Return only first-level subdirectories, sorted
list_subdirs() {
    local dir="$1"

    [[ -d "${dir}" ]] || return 0

    find "${dir}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

# Convert internal platform dir name to readable display name
display_platform_name() {
    local name="$1"

    case "${name}" in
        orin_nx_orin_nano)
            echo "Orin Nano / Orin NX (MIC-711, MIC-713)"
            ;;
        agx_orin)
            echo "AGX Orin (MIC-732, MIC-733, MIC-733AO)"
            ;;
        agx_thor)
            echo "AGX Thor (MIC-741, MIC-742, MIC-743)"
            ;;
        *)
            echo "${name}"
            ;;
    esac
}

get_current_platform_chipid() {
    local chipid

    if [[ ! -r /etc/nv_boot_control.conf ]]; then
        err "/etc/nv_boot_control.conf is missing or not readable."
        return 1
    fi

    chipid="$(
        awk '$1 == "TEGRA_CHIPID" { print $2; exit }' \
            /etc/nv_boot_control.conf
    )"

    if [[ -z "${chipid}" ]]; then
        err "Failed to read TEGRA_CHIPID from /etc/nv_boot_control.conf"
        return 1
    fi

    printf '%s\n' "${chipid}"
}

get_expected_chipid_for_platform() {
    local platform="$1"

    case "${platform}" in
        orin_nx_orin_nano) echo "0x23" ;;
        agx_orin)          echo "0x23" ;;
        agx_thor)          echo "0x26" ;;
        *)                 return 1 ;;
    esac
}

check_platform_chipid_match() {
    local selected_platform="$1"
    local current_chipid expected_chipid

    current_chipid="$(get_current_platform_chipid)" || return 1
    expected_chipid="$(get_expected_chipid_for_platform "${selected_platform}")" || {
        err "Unknown platform: ${selected_platform}"
        return 1
    }

    log "Detected current platform chipid : ${current_chipid}"
    log "Expected chipid for platform      : ${expected_chipid}"

    if [[ "${current_chipid}" != "${expected_chipid}" ]]; then
        warn "Platform mismatch detected."
        warn "Selected platform: $(display_platform_name "${selected_platform}")"
        warn "Current chipid   : ${current_chipid}"
        warn "Expected chipid  : ${expected_chipid}"
        return 1
    fi

    log "Platform chipid check passed."
    return 0
}


# Detect board and JetPack from /opt/version
# Example:
# MIC-743_Thor_7.2_V1.0.0, 1:2f23252, Build Date: 2026-06-10 15:05:45
detect_board_and_jetpack() {
    local version_file="/opt/version"
    local raw_version
    local version_header
    local board_name
    local field
    local jetpack_version=""
    local -a version_fields=()

    if [[ ! -r "${version_file}" ]]; then
        err "${version_file} is missing or not readable."
        return 1
    fi

    raw_version="$(head -n 1 "${version_file}")"
    raw_version="${raw_version//$'\r'/}"
    raw_version="${raw_version//$'\n'/}"

    if [[ -z "${raw_version}" ]]; then
        err "${version_file} is empty."
        return 1
    fi

    # Only process the content before the first comma.
    #
    # Examples:
    # MIC-743_Thor_7.2_V1.0.0
    # MIC-732_64G_Orin_6.0
    version_header="${raw_version%%,*}"

    IFS='_' read -r -a version_fields <<< "${version_header}"

    if [[ "${#version_fields[@]}" -lt 2 ]]; then
        err "Invalid ${version_file} format."
        err "Content: ${raw_version}"
        return 1
    fi

    # The first field is always the board model.
    board_name="${version_fields[0]}"

    # Search for the first field matching a JetPack version,
    # such as 6.0, 6.2, 7.0, 7.1, or 7.2.
    for field in "${version_fields[@]:1}"; do
        if [[ "${field}" =~ ^[0-9]+\.[0-9]+$ ]]; then
            jetpack_version="${field}"
            break
        fi
    done

    if [[ -z "${board_name}" ]]; then
        err "Failed to detect board name from ${version_file}."
        err "Content: ${raw_version}"
        return 1
    fi

    if [[ -z "${jetpack_version}" ]]; then
        err "Failed to detect JetPack version from ${version_file}."
        err "Content: ${raw_version}"
        return 1
    fi

    # Examples:
    # MIC-732   -> mic_732
    # MIC-733AO -> mic_733ao
    # MIC-743   -> mic_743
    DETECTED_BOARD="${board_name,,}"
    DETECTED_BOARD="${DETECTED_BOARD//-/_}"
    DETECTED_BOARD="${DETECTED_BOARD// /_}"

    if [[ ! "${DETECTED_BOARD}" =~ ^mic_[a-z0-9_]+$ ]]; then
        err "Unsupported board format in ${version_file}: ${board_name}"
        return 1
    fi

    # Examples:
    # 6.0 -> jp6.0
    # 7.2 -> jp7.2
    DETECTED_JETPACK="jp${jetpack_version}"

    SYSTEM_VERSION_RAW="${raw_version}"

    log "System information detected from ${version_file}:"
    log "  Raw     : ${SYSTEM_VERSION_RAW}"
    log "  Board   : ${board_name} (${DETECTED_BOARD})"
    log "  JetPack : ${jetpack_version} (${DETECTED_JETPACK})"

    return 0
}

detect_platform_from_board() {
    local board="$1"

    case "${board}" in
        mic_713|mic_711)
            echo "orin_nx_orin_nano"
            ;;

        mic_732|mic_733ao)
            echo "agx_orin"
            ;;

        mic_741|mic_742|mic_743)
            echo "agx_thor"
            ;;

        *)
            err "Unable to determine platform from board: ${board}"
            return 1
            ;;
    esac
}

get_package_board_from_detected_board() {
    local board="$1"

    case "${board}" in
        mic_741|mic_742|mic_743)
            echo "mic_742"
            ;;

        mic_711|mic_713)
            echo "${board}"
            ;;

        mic_732|mic_733|mic_733ao)
            echo "${board}"
            ;;

        *)
            err "No package board mapping for detected board: ${board}"
            return 1
            ;;
    esac
}

# Convert vendor dir name to display name
display_vendor_name() {
    local name="$1"
    case "${name}" in
        *)           echo "${name}" ;;
    esac
}

display_jetpack_name() {
    local name="$1"
    case "${name}" in
        jp*) echo "JetPack ${name#jp}" ;;
        *)   echo "${name}" ;;
    esac
}

# Show menu from array variable name, return selected item through stdout
# Return codes:
#   0 -> selected item printed to stdout
#   1 -> user chose Back/Exit (0)
show_menu() {
    local title="$1"
    shift
    local items=("$@")

    if [[ "${#items[@]}" -eq 0 ]]; then
        warn "No items found."
        return 1
    fi

    {
        echo
        echo "========================================"
        echo " ${title}"
        echo "========================================"

        local i=1
        for item in "${items[@]}"; do
            echo "${i}. ${item}"
            ((i++))
        done
        echo "0. Back/Exit"
        echo
    } >&2

    while true; do
        read -r -p "Please select [0-${#items[@]}]: " choice

        if [[ ! "${choice}" =~ ^[0-9]+$ ]]; then
            warn "Invalid input. Please enter a number."
            continue
        fi

        if [[ "${choice}" -eq 0 ]]; then
            return 1
        fi

        if (( choice >= 1 && choice <= ${#items[@]} )); then
            printf '%s\n' "${items[$((choice - 1))]}"
            return 0
        fi

        warn "Selection out of range."
    done
}

# Ask confirmation
confirm_run() {
    local vendor="$1"
    local sensor="$2"
    local platform="$3"

    {
        echo
        echo "You selected:"
        echo "  Vendor         : $(display_vendor_name "${vendor}")"
        echo "  Sensor         : ${sensor}"
        echo
        echo "Automatically detected:"
        echo "  Platform       : $(display_platform_name "${platform}")"
        echo "  Board          : ${DETECTED_BOARD}"
        echo "  Package board  : ${PACKAGE_BOARD}"
        echo "  JetPack        : $(display_jetpack_name "${DETECTED_JETPACK}")"
        echo
    } >&2

    while true; do
        read -r -p "Run installer now? [y/N]: " yn
        yn="${yn:-N}"

        case "${yn}" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO)   return 1 ;;
            *) warn "Please enter y or n." ;;
        esac
    done
}

# Run install.sh under selected package directory
run_install_script() {
    local pkg_dir="$1"
    local install_script="${pkg_dir}/install.sh"

    [[ -d "${pkg_dir}" ]] || die "Package directory not found: ${pkg_dir}"
    [[ -f "${install_script}" ]] || die "install.sh not found: ${install_script}"

    chmod +x "${install_script}"

    log "Running installer: ${install_script}"
    log "Log file: ${LOG_FILE}"

    (
        cd "${pkg_dir}"
        bash "./install.sh"
    ) 2>&1 | tee -a "${LOG_FILE}"
}


# -----------------------------
# Main UI flow
# -----------------------------
main() {
    require_root

    # Online mode: if the network is up, install the driver from the internal
    # server / GitHub instead of the bundled vendors/ tree, and never come back.
    if [[ -f "${SCRIPT_DIR}/online_mode.sh" ]] && online_reachable; then
        log "Network detected - switching to online mode (online_mode.sh)."
        exec bash "${SCRIPT_DIR}/online_mode.sh"
    fi

    [[ -d "${VENDORS_DIR}" ]] || \
        die "vendors directory not found: ${VENDORS_DIR}"

    log "Camera installer started."

    detect_board_and_jetpack || \
        die "Failed to detect Board and JetPack from ${VERSION_FILE}."

    DETECTED_PLATFORM="$(
        detect_platform_from_board "${DETECTED_BOARD}"
    )" || die "Failed to detect platform from board: ${DETECTED_BOARD}"

    PACKAGE_BOARD="$(
        get_package_board_from_detected_board "${DETECTED_BOARD}"
    )" || die "Failed to resolve package board from detected board: ${DETECTED_BOARD}"

    log "Detected platform : ${DETECTED_PLATFORM}"
    log "Detected board    : ${DETECTED_BOARD}"
    log "Package board     : ${PACKAGE_BOARD}"

    if ! check_platform_chipid_match "${DETECTED_PLATFORM}"; then
        die "Detected platform does not match the current TEGRA_CHIPID."
    fi

    while true; do
        mapfile -t vendor_ids < <(list_subdirs "${VENDORS_DIR}")

        if [[ "${#vendor_ids[@]}" -eq 0 ]]; then
            die "No vendors found under: ${VENDORS_DIR}"
        fi

        vendor_display=()

        for v in "${vendor_ids[@]}"; do
            vendor_display+=("$(display_vendor_name "${v}")")
        done

        if ! vendor_choice_display="$(
            show_menu "Select Vendor" "${vendor_display[@]}"
        )"; then
            log "User exited installer."
            exit 0
        fi

        selected_vendor=""

        for idx in "${!vendor_display[@]}"; do
            if [[ "${vendor_display[$idx]}" == "${vendor_choice_display}" ]]; then
                selected_vendor="${vendor_ids[$idx]}"
                break
            fi
        done

        [[ -n "${selected_vendor}" ]] || \
            die "Internal error: failed to resolve selected vendor."

        vendor_path="${VENDORS_DIR}/${selected_vendor}"

        while true; do
            mapfile -t sensor_ids < <(list_subdirs "${vendor_path}")

            if [[ "${#sensor_ids[@]}" -eq 0 ]]; then
                warn "No sensors found under vendor: ${selected_vendor}"
                break
            fi

            if ! selected_sensor="$(
                show_menu \
                    "Select Sensor under [$(display_vendor_name "${selected_vendor}")]" \
                    "${sensor_ids[@]}"
            )"; then
                break
            fi

            sensor_path="${vendor_path}/${selected_sensor}"

            selected_platform="${DETECTED_PLATFORM}"
            platform_path="${sensor_path}/${selected_platform}"
            board_path="${platform_path}/${PACKAGE_BOARD}"
            package_path="${board_path}/${DETECTED_JETPACK}"

            log "Automatically selected platform: $(display_platform_name "${selected_platform}")"

            if [[ ! -d "${platform_path}" ]]; then
                warn "The selected camera does not support the detected platform."
                warn "Vendor            : ${selected_vendor}"
                warn "Sensor            : ${selected_sensor}"
                warn "Detected platform : ${selected_platform}"
                warn "Expected path     : ${platform_path}"
                continue
            fi

            if [[ ! -d "${board_path}" ]]; then
                warn "The selected camera does not support the mapped package board."
                warn "Vendor         : ${selected_vendor}"
                warn "Sensor         : ${selected_sensor}"
                warn "Platform       : ${selected_platform}"
                warn "Detected board : ${DETECTED_BOARD}"
                warn "Package board  : ${PACKAGE_BOARD}"
                warn "Expected path  : ${board_path}"
                continue
            fi

            if [[ ! -d "${package_path}" ]]; then
                warn "The selected camera does not support the detected JetPack."
                warn "Detected board   : ${DETECTED_BOARD}"
                warn "Package board    : ${PACKAGE_BOARD}"
                warn "Detected JetPack : ${DETECTED_JETPACK}"
                warn "Expected path    : ${package_path}"
                continue
            fi

            if [[ ! -f "${package_path}/install.sh" ]]; then
                warn "install.sh not found under: ${package_path}"
                continue
            fi

            if ! confirm_run \
                "${selected_vendor}" \
                "${selected_sensor}" \
                "${selected_platform}"; then
                continue
            fi

            echo
            log "Selected vendor   : ${selected_vendor}"
            log "Selected sensor   : ${selected_sensor}"
            log "Detected board    : ${DETECTED_BOARD}"
            log "Package board     : ${PACKAGE_BOARD}"
            log "Detected JetPack  : ${DETECTED_JETPACK}"
            log "Selected path     : ${package_path}"

            if run_install_script "${package_path}"; then
                log "Installation finished successfully."
            else
                die "Installation failed."
            fi

            echo
            echo "Installation completed."
            echo "Log file: ${LOG_FILE}"
            echo "System may reboot automatically if triggered by vendor installer."
            echo

            exit 0
        done
    done
}

main "$@"
