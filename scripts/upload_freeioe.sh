#!/usr/bin/env bash
#
# Upload FreeIOE Release
# Uploads FreeIOE release package to remote server
#
# Usage: upload_freeioe.sh <version>
#
# Arguments:
#   version - FreeIOE version to upload (e.g., 1234)
#
# Process:
#   1. Copies release tarball and checksum to temporary directory
#   2. Uploads to kooiot.com:/var/www/openwrt/download/
#   3. Cleans up temporary directory
#
# Prerequisites:
#   - SSH access to kooiot.com
#   - Release must already exist in __release/freeioe/
#
# Examples:
#   upload_freeioe.sh 1234
#

set -e

# Get script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
echo "$SCRIPTPATH"

VERSION=$1
echo "$VERSION"

RELEASE_DIR=$SCRIPTPATH/../__release

# Create temporary upload directory
mkdir -p /tmp/__kooiot_openwrt_upload/freeioe

# Copy release files
cp -p "${RELEASE_DIR}/freeioe/${VERSION}.tar.gz"* /tmp/__kooiot_openwrt_upload/freeioe/

# Upload to remote server
scp -rp /tmp/__kooiot_openwrt_upload/freeioe kooiot.com:/var/www/openwrt/download/

# Cleanup
rm -rf /tmp/__kooiot_openwrt_upload/freeioe
