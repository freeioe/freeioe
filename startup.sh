#!/bin/sh
#
# FreeIOE Startup Script
# Usage: startup.sh <IOE_DIR>
#

# strict mode: exit on error, undefined variable is error
set -eu

# ============================================================================
# Constants
# ============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly WAIT_STRIP_TIMEOUT_SEC=300		# Max wait time for strip_done (seconds)
readonly VERSION_SUPPORT_ENV_AT=2547	# Skynet version which support @ env path

# Temporary files (respect TMPDIR environment variable)
: "${TMPDIR:=/tmp}"
readonly START_TIME_FILE="${TMPDIR}/ioe_start_time.txt"
readonly STARTUP_LOG="${TMPDIR}/ioe_startup.log"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${STARTUP_LOG}"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARN: $*"
}

log_error() {
    log "ERROR: $*"
}

# ============================================================================
# Utility Functions
# ============================================================================

# Print usage message
show_usage() {
    echo "Usage: ${SCRIPT_NAME} <IOE_DIR>" >&2
    echo "  IOE_DIR - Path to FreeIOE installation directory" >&2
}

# Check if a file exists and is executable
check_executable() {
    _file="$1"
    if [ -f "${_file}" ] && [ ! -x "${_file}" ]; then
        log_warn "File exists but not executable: ${_file}"
        chmod +x "${_file}"
    fi
}

# Wait for strip_done file with timeout
wait_for_strip_done() {
    _iode_dir="$1"
    _i=1

    while [ "${_i}" -le "${WAIT_STRIP_TIMEOUT_SEC}" ]; do
        if [ -f "${_iode_dir}/ipt/strip_done" ]; then
            if [ "${_i}" -gt 1 ]; then
                sync
            fi
            log_info "strip_done found after ${_i}s"
            return 0
        fi
        sleep 1
        _i=$((_i + 1))
    done

    log_warn "strip_done not found after ${WAIT_STRIP_TIMEOUT_SEC}s timeout"
    return 1
}

# Run a script with error handling
run_script() {
    _script="$1"
    _script_name="$(basename "${_script}")"

    log_info "Running ${_script_name}..."
    if sh "${_script}" >> "${STARTUP_LOG}" 2>&1; then
        log_info "${_script_name} completed successfully"
        return 0
    else
        _exit_code=$?
        log_error "${_script_name} failed with exit code ${_exit_code}"
        return "${_exit_code}"
    fi
}

# ============================================================================
# Input Validation
# ============================================================================

if [ $# -eq 0 ]; then
    log_error "Missing required argument: IOE_DIR"
    show_usage
    exit 1
fi

IOE_DIR="$1"

if [ ! -d "${IOE_DIR}" ]; then
    log_error "Directory not found: ${IOE_DIR}"
    exit 1
fi

# Change to IOE directory
if ! cd "${IOE_DIR}"; then
    log_error "Failed to change directory to: ${IOE_DIR}"
    exit 1
fi

log_info "FreeIOE Startup Script - Starting..."
log_info "IOE_DIR: ${IOE_DIR}"

# Record start time
{
    date
    date +%s
} > "${START_TIME_FILE}"

# ============================================================================
# Wait for strip_done (if in strip mode)
# ============================================================================

if [ -f "${IOE_DIR}/ipt/strip_mode" ]; then
    log_info "Strip mode detected, waiting for strip_done..."
    wait_for_strip_done "${IOE_DIR}"
fi

# ============================================================================
# User Startup Script
# ============================================================================

if [ -f "${IOE_DIR}/ipt/startup.sh" ]; then
    check_executable "${IOE_DIR}/ipt/startup.sh"
    run_script "${IOE_DIR}/ipt/startup.sh" || exit $?
fi

# ============================================================================
# Upgrade
# ============================================================================

if [ -f "${IOE_DIR}/ipt/upgrade" ]; then
    log_info "Upgrade flag detected! Starting upgrade process..."

    if [ -f "${IOE_DIR}/ipt/upgrade.sh" ]; then
        run_script "${IOE_DIR}/ipt/upgrade.sh"
        _upgrade_status=$?

        # Remove upgrade flag regardless of result
        rm -f "${IOE_DIR}/ipt/upgrade"

        if [ "${_upgrade_status}" -ne 0 ]; then
            log_error "Upgrade failed, aborting startup"
            exit "${_upgrade_status}"
        fi
    else
        log_warn "Upgrade flag exists but upgrade.sh not found"
        rm -f "${IOE_DIR}/ipt/upgrade"
    fi
else
    log_info "No upgrade needed"
fi

# ============================================================================
# Rollback
# ============================================================================

if [ -f "${IOE_DIR}/ipt/rollback" ]; then
    log_info "Rollback flag detected! Starting rollback process..."

    if [ -f "${IOE_DIR}/ipt/rollback.sh" ]; then
        if run_script "${IOE_DIR}/ipt/rollback.sh"; then
            rm -f "${IOE_DIR}/ipt/rollback"
            log_info "Rollback completed successfully"
        else
            _rollback_status=$?
            log_error "Rollback failed with exit code ${_rollback_status}"
            exit "${_rollback_status}"
        fi
    else
        log_error "Rollback flag exists but rollback.sh not found"
        exit 1
    fi
else
    log_info "No rollback needed"
fi

# ============================================================================
# Skynet Config Compat
# ============================================================================
if [ -f "${IOE_DIR}/skynet/ioe/config.path.compat" ]; then
    log_info "Found config.path.compat file"

	# Source functions script (do not need check functions.sh exits)
	. "${IOE_DIR}/skynet/ioe/scripts/functions.sh"

    # Read skynet version
    set -- $(read_version "${IOE_DIR}/skynet/version")
    _skynet_ver=$1
    log_info "Skynet version: ${_skynet_ver}"

    if [ "${_skynet_ver}" -lt "${VERSION_SUPPORT_ENV_AT}" ]; then
        log_info "Applying config.path.compat (version ${_skynet_ver} < ${VERSION_SUPPORT_ENV_AT})"

        # Backup existing config.path if present
        if [ -f "${IOE_DIR}/skynet/ioe/config.path" ]; then
            _backup_file="${IOE_DIR}/skynet/ioe/config.path.backup"
            log_info "Backing up config.path to: $(basename "${_backup_file}")"

            if ! mv "${IOE_DIR}/skynet/ioe/config.path" "${_backup_file}"; then
				# only log error, and skip this error
                log_error "Failed to backup config.path"
            fi
        fi

        # Apply compat config
        if ! mv "${IOE_DIR}/skynet/ioe/config.path.compat" "${IOE_DIR}/skynet/ioe/config.path"; then
            log_error "Failed to apply config.path.compat"
            exit 1
        fi

        log_info "Successfully applied config.path.compat"
    fi
fi

# ============================================================================
# Environment Variables
# ============================================================================

if [ -f "${IOE_DIR}/.env" ]; then
    log_info "Loading environment variables from .env"
    # shellcheck source=/dev/null
    set -o allexport && . "${IOE_DIR}/.env" && set +o allexport
fi

# ============================================================================
# Finalize
# ============================================================================

log_info "Startup script completed successfully"
sync

exit 0
