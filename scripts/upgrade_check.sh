#!/bin/sh
# Check if FreeIOE and Skynet versions are compatible

FREEIOE_PATH=$1
SKYNET_PATH=$2

# Read version file: first line is version number, second line is branch
read_version() {
    local fn="$1"
    local v=0
    local branch="develop"

    if [ -f "$fn" ] && [ -r "$fn" ]; then
        read -r v branch < "$fn" 2>/dev/null
        # Validate version is numeric
        case "$v" in
            ''|*[!0-9]*) v=0 ;;
        esac
        # Use default branch if empty
        [ -z "$branch" ] && branch="develop"
    fi

    echo "$v"
    echo "$branch"
}

# Get FreeIOE version
set -- $(read_version "${FREEIOE_PATH}/version")
fver=$1
fbranch=$2

# Get Skynet version
set -- $(read_version "${SKYNET_PATH}/version")
sver=$1
sbranch=$2

# FreeIOE > 1609 requires Skynet >= 2547 (for @path config support)
if [ "$fver" -gt 1609 ] && [ "$sver" -lt 2547 ]; then
    exit 1
fi

exit 0
