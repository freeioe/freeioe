#!/bin/sh
#
# FreeIOE Upgrade Check Script
# Checks compatibility between FreeIOE and Skynet versions
#
# Usage: upgrade_check.sh <FREEIOE_PATH> <SKYNET_PATH>
#

# Strict mode: exit on error, undefined variable is error
set -eu

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
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
# Input Validation
# ============================================================================

if [ $# -ne 2 ]; then
    log_error "Usage: $0 <FREEIOE_PATH> <SKYNET_PATH>"
    exit 1
fi

FREEIOE_PATH="$1"
SKYNET_PATH="$2"

if [ ! -d "${FREEIOE_PATH}" ]; then
    log_error "FreeIOE directory not found: ${FREEIOE_PATH}"
    exit 1
fi

if [ ! -d "${SKYNET_PATH}" ]; then
    log_error "Skynet directory not found: ${SKYNET_PATH}"
    exit 1
fi

# Source functions.sh for read_version function
. "${FREEIOE_PATH}/scripts/functions.sh"

# ============================================================================
# Version Compatibility Check
# ============================================================================

# Get FreeIOE version
set -- $(read_version "${FREEIOE_PATH}/version")
fver=$1
fbranch=$2

# Get Skynet version
set -- $(read_version "${SKYNET_PATH}/version")
sver=$1
sbranch=$2

log_info "Upgrade checking... FreeIOE ver:${fver} Skynet ver:${sver}"

# FreeIOE > 1609 requires Skynet >= 2547 (for @ path config support)
readonly VERSION_ENV_AT=1609      # FreeIOE version threshold
readonly SKYNET_VERSION_ENV_AT=2547      # Required Skynet version for @path config support
if [ "${fver}" -gt "${VERSION_ENV_AT}" ] && [ "${sver}" -lt "${SKYNET_VERSION_ENV_AT}" ]; then
    if [ -f "${FREEIOE_PATH}/config.path.compat" ]; then
        log_info "Applying config.path.compat for older Skynet version"

        # Backup existing config.path if present
        if [ -f "${FREEIOE_PATH}/config.path" ]; then
            backup_file="${FREEIOE_PATH}/config.path.backup"
            log_info "Backing up existing config.path to: $(basename "${backup_file}")"

            if ! mv "${FREEIOE_PATH}/config.path" "${backup_file}"; then
                log_error "Failed to backup config.path"
            fi
        fi

        # Apply compat config
        if ! mv "${FREEIOE_PATH}/config.path.compat" "${FREEIOE_PATH}/config.path"; then
            log_error "Failed to apply config.path.compat"
            exit 1
        fi

        log_info "Successfully applied config.path.compat"
    else
        log_warn "config.path.compat not found, upgrade may fail"
    fi
fi

log_info "FreeIOE upgrade check completed successfully"
exit 0
