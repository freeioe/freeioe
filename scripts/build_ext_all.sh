#!/usr/bin/env bash
#
# Build All Extensions
# Iterates over all supported platforms and builds extension libraries
#
# Usage: build_ext_all.sh [build_lib]
#
# Arguments:
#   build_lib - Optional. Specify "opcua" to build OPC-UA extension
#
# Process:
#   1. Loads platform definitions from plats.sh
#   2. For each platform:
#      - Optionally builds OPC-UA extension if specified
#      - Builds standard extension libraries
#      - Copies output to prebuild_exts directory
#
# Examples:
#   build_ext_all.sh           # Build standard extensions for all platforms
#   build_ext_all.sh opcua     # Also build OPC-UA extension
#

set -e

# Get script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
echo "$SCRIPTPATH"

BUILD_LIB=$1
CUR_DIR=$(pwd)

# Load all supported platforms
source "$SCRIPTPATH/plats.sh"

# Build for each platform
for item in "${!plats[@]}"; do
	# Build OPC-UA extension if requested
	if [ "$BUILD_LIB" = "opcua" ]; then
		bash "$SCRIPTPATH/build_ext_opcua.sh" "$item" "${plats[$item]}" "$CUR_DIR/../.."
	fi

	# Build standard extension libraries
	mkdir -p "$SCRIPTPATH/../feeds/prebuild_exts/$item/"
	bash "$SCRIPTPATH/build_ext.sh" "$item" "${plats[$item]}" "$SCRIPTPATH/../feeds/prebuild_exts/$item/"
done
