#!/usr/bin/env bash
#
# Release Skynet Framework
# Creates a release package for the Skynet framework
#
# Usage: release_skynet.sh <skynet_dir> [platform] [release_dir]
#
# Arguments:
#   skynet_dir   - Path to Skynet source directory
#   platform     - Optional. Platform identifier (default: "skynet")
#   release_dir  - Optional. Base release directory (default: <skynet_dir>/ioe/__release)
#
# Process:
#   1. Calculates version from git commit count
#   2. Generates revision from last commit timestamp
#   3. Creates __install directory with Skynet files:
#      - lualib, luaclib, service, cservice
#      - README.md, HISTORY.md, LICENSE
#      - skynet executable
#      - Symlinks for ioe and logs
#   4. Creates release tarball with MD5 checksum
#   5. Copies to "latest" for easy access
#
# Output:
#   <release_dir>/bin/<platform>/<version>.tar.gz
#   <release_dir>/bin/<platform>/latest.tar.gz -> <version>.tar.gz
#
# Examples:
#   release_skynet.sh ./skynet
#   release_skynet.sh ./skynet openwrt/19.07/arm_cortex-a7_neon-vfpv4 ./release
#

set -e

SKYNET_DIR=$1
SKYNET_PLAT="skynet"

# Parse optional arguments
if [ -n "$2" ]; then
	SKYNET_PLAT="$2/skynet"
fi

if [ -n "$3" ]; then
	RELEASE_DIR="$3"
else
	RELEASE_DIR="$1/ioe/__release"
fi

RELEASE_DIR="$RELEASE_DIR/bin/$SKYNET_PLAT"

echo "--------------------------------------------"
echo "Skynet IN: $SKYNET_DIR  PLAT: $SKYNET_PLAT  ReleaseDir: $RELEASE_DIR"

cd "$SKYNET_DIR"

### Get the version by count the commits
# Calculate version from git commit count
VERSION=$(git log --oneline | wc -l | tr -d ' ')

### Generate the revision by last commit
# Generate revision from last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

echo "Version: $VERSION"
echo "Revision: $REVISION"

# Check if this version is already released
if [ -f "$RELEASE_DIR/$VERSION.tar.gz" ]; then
	echo 'Skynet already released'
	exit
fi

# Clean up the cramfs folder
#sudo rm -rf __install
# Prepare install directory
rm -rf __install
mkdir __install

# Copy files
# Write version information
echo "$VERSION" > __install/version
echo "$REVISION" >> __install/version

# Copy Skynet files
cp -r -L lualib __install/lualib
cp -r luaclib __install/luaclib
cp -r service __install/service
cp -r cservice __install/cservice
cp README.md __install/
cp HISTORY.md __install/
cp LICENSE __install/
cp skynet __install/

# Create symbolic links
cd __install/
ln -s ../freeioe ./ioe
ln -s /var/log ./logs
cd - > /dev/null

# Compile lua files
# ./scripts/compile_lua.sh

#################################
# Count the file sizes
################################
du __install -sh

# find __install -type f |xargs -I{} file "{}"|grep "ELF\|ar "|sed 's/\(.*\):.*/\1/'|xargs $STRIP
# du __install -sh

###################
##
##################

# Create release tarball
cd __install
mkdir -p "$RELEASE_DIR"
tar czvf "$RELEASE_DIR/$VERSION.tar.gz" * > /dev/null
md5sum -b "$RELEASE_DIR/$VERSION.tar.gz" > "$RELEASE_DIR/$VERSION.tar.gz.md5"
du "$RELEASE_DIR/$VERSION.tar.gz" -sh
cat "$RELEASE_DIR/$VERSION.tar.gz.md5"
## Copy to latest
# Copy to latest for convenience
cp -f "$RELEASE_DIR/$VERSION.tar.gz" "$RELEASE_DIR/latest.tar.gz"
cp -f "$RELEASE_DIR/$VERSION.tar.gz.md5" "$RELEASE_DIR/latest.tar.gz.md5"
echo "$VERSION" > "$RELEASE_DIR/latest.version"
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
# Cleanup
rm -rf __install
