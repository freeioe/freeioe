#!/usr/bin/env bash
#
# Release Application
# Creates a release package for an application from a feed directory
#
# Usage: release_app.sh <feed_dir> <app_name>
#
# Arguments:
#   feed_dir - Feed directory name (e.g., example_apps, hj212_apps)
#   app_name - Application name within the feed
#
# Process:
#   1. Changes to feed directory
#   2. Calculates version from git commit count
#   3. Generates revision from last commit timestamp
#   4. Creates release archive with version information
#   5. Generates MD5 checksum
#   6. Copies to "latest" for easy access
#
# Output:
#   __release/<feed_dir>/<app_name>/<version>.zip
#   __release/<feed_dir>/<app_name>/latest.zip -> <version>.zip
#
# Examples:
#   release_app.sh example_apps ioe
#

set -e

# Validate arguments
if [ $# -lt 1 ] ; then
	echo "Usage: release_app.sh <feed dir> <app name>"
	exit 0
fi

BASE_DIR=$(pwd)
FEEDS_DIR=$1
RELEASE_DIR="$BASE_DIR/__release/$1/$2"

mkdir -p "$RELEASE_DIR"
# echo 'Base Dir:'$BASE_DIR
# echo 'Release Dir:'$BASE_DIR

# cd ./feeds/example_apps/$1
# Change to application feed directory
cd ./feeds/"$FEEDS_DIR"/"$2"

### Get the version by count the commits
# Calculate version from git commit count
VERSION=$(git log --oneline | wc -l | tr -d ' ')

### Generate the revision by last commit
# Generate revision from last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

# echo 'Version:'$VERSION
# echo 'Revision:'$REVISION
echo "Release App: $1 Version: $VERSION Revision: $REVISION"

# Check if this version is already released
if [ -f "$RELEASE_DIR/$VERSION.zip" ]; then
	echo "$1/$VERSION.zip already released"
	exit
fi

# Create temporary install directory
mkdir ../__install_temp

# Export application to temporary directory
git archive HEAD | tar -x -C ../__install_temp

cd ../__install_temp

# zip files
# Write version information
echo "$VERSION" > version
echo "$REVISION" >> version

# Create release archive
zip -r -q "$RELEASE_DIR/$VERSION.zip" *

cd -
rm -rf ../__install_temp

# Generate checksum
md5sum -b "$RELEASE_DIR/$VERSION.zip" > "$RELEASE_DIR/$VERSION.zip.md5"
du "$RELEASE_DIR/$VERSION.zip" -sh
cat "$RELEASE_DIR/$VERSION.zip.md5"

## Copy to latest
# Copy to latest for convenience
cp -f "$RELEASE_DIR/$VERSION.zip" "$RELEASE_DIR/latest.zip"
cp -f "$RELEASE_DIR/$VERSION.zip.md5" "$RELEASE_DIR/latest.zip.md5"
echo "$VERSION" > "$RELEASE_DIR/latest.version"

cd "$BASE_DIR"

