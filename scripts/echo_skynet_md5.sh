#!/usr/bin/env bash
#
# Generate Skynet MD5 Checksums
# Creates MD5SUM file containing checksums for all Skynet releases
#
# Usage: echo_skynet_md5.sh <version>
#
# Arguments:
#   version - Version number to generate checksums for (e.g., 1234)
#
# Output:
#   Creates ./MD5SUM file with format: <md5> <openwrt_ver> <arch>
#
# Process:
#   1. Loads platform definitions from plats.sh
#   2. For each platform, extracts MD5 from existing .md5 file
#   3. Writes to MD5SUM file: <md5sum> <version> <architecture>
#
# Examples:
#   echo_skynet_md5.sh 1234
#
# Output format:
#   a1b2c3d4... 19.07 arm_cortex-a7_neon-vfpv4
#   e5f6g7h8... 19.07 x86_64
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

# Clear existing MD5SUM file
rm -f ./MD5SUM

# Generate checksums for all platforms
for item in "${!plats[@]}"; do
    # Extract MD5 from existing .md5 file
    MD5SUM="$(cat "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz.md5" | awk '{print $1}')"
    ls -lh "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"

    # Parse platform string to extract version and architecture
    VER="$(echo "${item}" | awk -F/ '{print $2}')"
    ARCH="$(echo "${item}" | awk -F/ '{print $3}')"
    echo "${MD5SUM} ${VER} ${ARCH}" >> ./MD5SUM
done
