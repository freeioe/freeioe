#!/bin/sh
#
# Common Utility Functions
# Library of shared functions used by other scripts
#
# Usage:
#   source scripts/functions.sh
#
# Functions:
#   read_version <file>
#       Reads version information from a file
#       Returns: <version> <branch> (on stdout, two lines)
#
# Version File Format:
#   Line 1: Version number (integer)
#   Line 2: Branch name (e.g., "develop", "master")
#
# Examples:
#   source scripts/functions.sh
#   set -- $(read_version version.txt)
#   version=$1
#   branch=$2
#

# Read version file: first line is version number, second line is branch
#
# Arguments:
#   file - Path to version file
#
# Outputs:
#   Line 1: Version number (integer, 0 if invalid)
#   Line 2: Branch name (defaults to "develop" if empty)
#
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
