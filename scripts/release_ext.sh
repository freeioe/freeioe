#!/usr/bin/env bash
#
# Release Extension
# Creates a release package for a compiled extension library
#
# Usage: release_ext.sh <ext_name> <platform> <type>
#
# Arguments:
#   ext_name - Extension name (e.g., opcua, snap7, plctag, frpc, sqlite3)
#   platform - Target platform (default: openwrt)
#   type     - Extension type:
#              "luaclib" - Lua C library (.so files)
#              "bin"     - Executable binary
#              "raw"     - Raw files (copy as-is)
#
# Process:
#   1. Calculates version from git commit count (offset by 40000)
#   2. Generates revision from last commit timestamp
#   3. Creates tarball with extension files and version info
#   4. Generates MD5 checksum
#   5. Copies to "latest" for easy access
#
# Output:
#   __release/bin/<platform>/<ext_name>/<version>.tar.gz
#
# Examples:
#   release_ext.sh opcua openwrt/19.07/arm_cortex-a7_neon-vfpv4 luaclib
#   release_ext.sh frpc openwrt/19.07/x86_64 bin
#

set -e

# Validate arguments
if [ $# -lt 3 ] ; then
	echo "Usage: release_ext.sh <ext name> <platform> <type>"
	exit 0
fi

TARGET_EXT=$1
TARGET_PLAT=$2
TARGET_TYPE=$3

BASE_DIR=$(pwd)
RELEASE_DIR="__release"
TARGET_FOLDER="bin/$TARGET_PLAT/$1"

# echo "Release Extension:" $TARGET_FOLDER

# Change to platform's prebuilt extensions directory
cd ./feeds/prebuild_exts/"$TARGET_PLAT"

### Get the version by count the commits
# Calculate version from git commit count (offset by 40000 for extensions)
VERSION=$(git log --oneline | wc -l | tr -d ' ')
VERSION=$(expr 40000 + "${VERSION}")

### Generate the revision by last commit
# Generate revision from last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

# echo 'Version:'$VERSION
# echo 'Revision:'$REVISION
echo "Release Extension: $TARGET_FOLDER Version: $VERSION Revision: $REVISION"

cd "$BASE_DIR"

# Check if this version is already released
if [ -f "$RELEASE_DIR/$TARGET_FOLDER/$VERSION.tar.gz" ]; then
	echo "$TARGET_FOLDER/$VERSION.tar.gz already released"
	exit
fi

# tar gz files
# Create release directory structure
mkdir -p "$RELEASE_DIR/$TARGET_FOLDER"
rm -rf "$RELEASE_DIR/$TARGET_FOLDER/temp"
mkdir -p "$RELEASE_DIR/$TARGET_FOLDER/temp"

# Write version information
echo "$VERSION" > "$RELEASE_DIR/$TARGET_FOLDER/temp/version"
echo "$REVISION" >> "$RELEASE_DIR/$TARGET_FOLDER/temp/version"

# Copy files based on extension type
if [ "$TARGET_TYPE" = "luaclib" ] ; then
	# Copy Lua C library (.so files)
	mkdir -p "$RELEASE_DIR/$TARGET_FOLDER/temp/luaclib"
	cp ./feeds/prebuild_exts/"$TARGET_PLAT"/"$TARGET_EXT".so "$RELEASE_DIR/$TARGET_FOLDER/temp/luaclib/"
fi

if [ "$TARGET_TYPE" = "bin" ] ; then
	# Copy executable binary
	mkdir -p "$RELEASE_DIR/$TARGET_FOLDER/temp/bin"
	cp ./feeds/prebuild_exts/"$TARGET_PLAT"/"$TARGET_EXT" "$RELEASE_DIR/$TARGET_FOLDER/temp/bin/"
fi

if [ "$TARGET_TYPE" = "raw" ] ; then
	# Copy all files as-is
	cp -r ./feeds/prebuild_exts/"$TARGET_PLAT"/"$TARGET_EXT"/* "$RELEASE_DIR/$TARGET_FOLDER/temp/"
fi

# Create release tarball
cd "$RELEASE_DIR/$TARGET_FOLDER/temp"
# find . -type f |xargs -I{} file "{}"|grep "ELF\|ar "|sed 's/\(.*\):.*/\1/'|xargs $STRIP
# du __install -sh

tar czvf "../$VERSION.tar.gz" * > /dev/null
md5sum -b "../$VERSION.tar.gz" > "../$VERSION.tar.gz.md5"
du "../$VERSION.tar.gz" -sh
cat "../$VERSION.tar.gz.md5"
## Copy to latest
# Copy to latest for convenience
cp -f "../$VERSION.tar.gz" "../latest.tar.gz"
cp -f "../$VERSION.tar.gz.md5" "../latest.tar.gz.md5"
echo "$VERSION" > "../latest.version"

cd "$BASE_DIR"
