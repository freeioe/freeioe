#!/usr/bin/env bash
#
# Build Skynet for All Platforms
# Iterates over all supported platforms and builds Skynet framework
#
# Usage: build_skynet_all.sh
#
# Process:
#   1. Loads platform definitions from plats.sh
#   2. For each platform:
#      - Calls build_skynet.sh with platform-specific toolchain
#      - Builds and packages Skynet for that platform
#
# Output:
#   Creates release packages in __release/bin/<platform>/skynet/
#
# Prerequisites:
#   - Skynet source must be in current directory
#   - Toolchain files must be in ~/toolchains/
#   - Platform definitions in plats.sh
#
# Examples:
#   cd /path/to/freeioe
#   ./scripts/build_skynet_all.sh
#

set -e

# Get script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
echo "$SCRIPTPATH"

SKYNET_DIR=$(pwd)

# Load all supported platforms
source "$SCRIPTPATH/plats.sh"

# Build Skynet for each platform
for item in "${!plats[@]}"; do
	bash "$SCRIPTPATH/build_skynet.sh" "$item" "${plats[$item]}" "$SKYNET_DIR" "$SCRIPTPATH/../"
done
