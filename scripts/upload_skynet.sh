#!/usr/bin/env bash
#
# Upload Skynet Releases
# Uploads Skynet release packages for all platforms to remote server
#
# Usage: upload_skynet.sh <version>
#
# Arguments:
#   version - Skynet version to upload (e.g., 1234)
#
# Process:
#   1. Loads platform definitions from plats.sh
#   2. For each platform:
#      - Copies Skynet tarball and checksum to temporary directory
#      - Organizes by platform structure
#   3. Uploads entire directory structure to kooiot.com
#   4. Cleans up temporary directory
#
# Prerequisites:
#   - SSH access to kooiot.com
#   - Skynet releases must exist in __release/bin/<platform>/skynet/
#
# Output on server:
#   /var/www/openwrt/download/bin/<platform>/skynet/<version>.tar.gz
#
# Examples:
#   upload_skynet.sh 1234
#

set -e

# Get script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
echo "$SCRIPTPATH"

VERSION=$1
echo "$VERSION"

RELEASE_DIR=$SCRIPTPATH/../__release/bin

# Create temporary upload directory
mkdir -p /tmp/__kooiot_openwrt_upload/bin

# Load all supported platforms
source "$SCRIPTPATH/plats.sh"

# Copy release files for each platform
for item in "${!plats[@]}"; do
	ls -lh "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"

	mkdir -p /tmp/__kooiot_openwrt_upload/bin/"${item}"/skynet/

	cp -p "${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"* /tmp/__kooiot_openwrt_upload/bin/"${item}"/skynet/

	ls -lh /tmp/__kooiot_openwrt_upload/bin/"${item}"/skynet/"${VERSION}".tar.gz
done

# Upload to remote server
scp -rp /tmp/__kooiot_openwrt_upload/bin kooiot.com:/var/www/openwrt/download/

# Cleanup
rm -rf /tmp/__kooiot_openwrt_upload
