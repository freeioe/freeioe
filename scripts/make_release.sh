#!/usr/bin/env sh
#
# Make FreeIOE Release
# Creates a complete FreeIOE release package with all components
#
# Usage: make_release.sh
#
# Process:
#   1. Calculates version from git commit count
#   2. Generates revision from last commit timestamp
#   3. Creates __install directory from git archive
#   4. Removes unnecessary files (tests, docs, etc.)
#   5. Compiles Lua files (optional, currently commented)
#   6. Releases applications and extensions for all platforms
#   7. Creates release tarball with MD5 checksum
#   8. Copies to "latest" for easy access
#
# Output:
#   __release/freeioe/<version>.tar.gz
#   __release/freeioe/<version>.tar.gz.md5
#   __release/freeioe/latest.tar.gz -> <version>.tar.gz
#   __release/freeioe/latest.version
#
# Platforms supported:
#   - linux/x86_64
#   - openwrt/17.01/arm_cortex-a9_neon
#   - openwrt/19.07/x86_64
#   - openwrt/19.07/arm_cortex-a7_neon-vfpv4
#   - openwrt/snapshot/mipsel_24kc
#   - openwrt/snapshot/arm_cortex-a7_neon-vfpv4
#

set -e

echo "--------------------------------------------"
echo "FreeIOE in: $PWD"

# Calculate version from git commit count
VERSION=$(git log --oneline | wc -l | tr -d ' ')

# Generate revision from last commit
# Format: git-YY.JJJ_HHMMM-commit_hash
#   YY: last 2 digits of year
#   JJJ: day of year
#   HHMMM: seconds mod 86400 (5 digits)
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

echo "Version: $VERSION"
echo "Revision: $REVISION"

#rm __release/* -rf
# Make the release folder
mkdir -p __release/freeioe

# Clean up the cramfs folder
#sudo rm -rf __install
# Prepare install directory
rm -rf __install
mkdir __install

# Copy files
# Export current git tree to install directory
git archive HEAD | tar -x -C __install

# copy upgrade check script
# Preserve essential scripts
mkdir -p __install/scripts.keep
cp __install/scripts/functions.sh __install/scripts.keep/
cp __install/scripts/upgrade_check.sh __install/scripts.keep/

# Delete files
# Remove unnecessary files
rm -rf __install/test
rm -rf __install/scripts
# rm -rf __install/www
rm -f __install/feeds.conf.default
rm -rf __install/doc/app/example_app.lua

# move scripts.keep to scripts
# Restore preserved scripts
mv __install/scripts.keep __install/scripts
# copy example app file
# Copy example app from feeds
cp feeds/example_apps/sample/app.lua __install/doc/app/example_app.lua

# Echo version
# Write version information
echo "$VERSION" > __install/version
echo "$REVISION" >> __install/version

# copy lwf files
# Copy LWF (Lua Web Framework) files
rm -f __install/lualib/lwf.lua
rm -f __install/lualib/lwf
rm -f __install/lualib/resty
cp lualib/lwf.lua __install/lualib/lwf.lua
cp -rL lualib/lwf __install/lualib/lwf
cp -rL lualib/resty __install/lualib/resty

# Compile lua files
# Compile Lua files (optional, currently disabled)
# ./scripts/compile_lua.sh

# Release Applications


# Release Applications

./feeds/example_apps/release.sh ./scripts/release_app.sh example_apps
./feeds/hj212_apps/release.sh ./scripts/release_app.sh hj212_apps
./feeds/viccom_apps/release.sh ./scripts/release_app.sh viccom_apps

# Validate platform name
# Supported platforms for extensions
PLAT_NAMES="linux/x86_64 openwrt/17.01/arm_cortex-a9_neon openwrt/19.07/x86_64 openwrt/19.07/arm_cortex-a7_neon-vfpv4 openwrt/snapshot/mipsel_24kc openwrt/snapshot/arm_cortex-a7_neon-vfpv4"

# Release Extensions
# Release extensions for all platforms
for plat in $PLAT_NAMES; do
	./scripts/release_ext.sh opcua "$plat" "luaclib"
	./scripts/release_ext.sh snap7 "$plat" "luaclib"
	./scripts/release_ext.sh plctag "$plat" "luaclib"
	./scripts/release_ext.sh frpc "$plat" "bin"
	./scripts/release_ext.sh sqlite3 "$plat" "raw"
done

# For pre-installed applications
# Pre-install ioe application
mkdir __install/apps
./scripts/pre_inst.sh "example_apps/ioe" "ioe"

# For ioe extensions
# Create extensions directory
mkdir __install/ext

#################################
# Count the file sizes
################################
du __install -sh

###################
##
##################

# Check if release already exists
if [ -f "__release/freeioe/$VERSION.tar.gz" ]; then
	rm -rf __install
	echo "freeioe/$VERSION.tar.gz already released"
	exit
fi

# Create release tarball
cd __install
tar czvf "../__release/freeioe/$VERSION.tar.gz" * > /dev/null
md5sum -b "../__release/freeioe/$VERSION.tar.gz" > "../__release/freeioe/$VERSION.tar.gz.md5"
du "../__release/freeioe/$VERSION.tar.gz" -sh
cat "../__release/freeioe/$VERSION.tar.gz.md5"
## Copy to latest
# Copy to latest for convenience
cp -f "../__release/freeioe/$VERSION.tar.gz" "../__release/freeioe/latest.tar.gz"
cp -f "../__release/freeioe/$VERSION.tar.gz.md5" "../__release/freeioe/latest.tar.gz.md5"
echo "$VERSION" > "../__release/freeioe/latest.version"
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
# Cleanup
rm -rf __install

echo 'May GOD with YOU always!'
