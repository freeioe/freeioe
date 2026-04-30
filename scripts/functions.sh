#!/bin/sh

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
