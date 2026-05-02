#!/usr/bin/env bash
#
# Clean Skynet Release Files by Version
# Removes Skynet release archives for a specific version across all platforms
#
# Usage: clean_skynet_by_version.sh <version>
#
# Arguments:
#   version - Version number to clean (e.g., 1234)
#
# Process:
#   1. Loads platform definitions from plats.sh
#   2. For each platform, removes:
#      - __release/bin/<platform>/skynet/<version>.tar.gz
#      - __release/bin/<platform>/skynet/<version>.tar.gz.md5
#
# Examples:
#   clean_skynet_by_version.sh 1234
#

set -e

# Get script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
echo "$SCRIPTPATH"

VERSION=$1
echo "$VERSION"

RELEASE_DIR=$SCRIPTPATH/../__release/bin

# Load all supported platforms
source "$SCRIPTPATH/plats.sh"

# Remove release files for specified version across all platforms
for item in "${!plats[@]}"; do
    echo "Deleting ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"
    rm "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz.md5"
    rm "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"
done
