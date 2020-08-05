# !/usr/bin/env sh

echo "--------------------------------------------"
echo "FreeIOE System IN:" $PWD

### Get the version by count the commits
VERSION=`git log --oneline | wc -l | tr -d ' '`

### Generate the revision by last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

echo 'Version:'$VERSION
echo 'Revision:'$REVISION

#rm __release/* -rf
# Make the release folder
mkdir -p __release/freeioe

# Clean up the cramfs folder
#sudo rm -rf __install
rm -rf __install
mkdir __install

# Copy files
git archive HEAD | tar -x -C __install
rm -rf __install/test
rm -rf __install/scripts
# rm -rf __install/www

rm -rf __install/doc/app/example_app.lua
cp feeds/example_apps/sample/app.lua __install/doc/app/example_app.lua

# Echo version
echo $VERSION > __install/version
echo $REVISION >> __install/version

# copy lwf files
rm -f __install/lualib/lwf.lua
rm -f __install/lualib/lwf
rm -f __install/lualib/resty
cp lualib/lwf.lua __install/lualib/lwf.lua
cp -rL lualib/lwf __install/lualib/lwf
cp -rL lualib/resty __install/lualib/resty

# Compile lua files
# ./scripts/compile_lua.sh 

# Release Applications

./feeds/example_apps/release.sh ./scripts/release_app.sh

# Validate platform name
PLAT_NAMES="linux/x86_64 openwrt/17.01/arm_cortex-a9_neon openwrt/18.06/x86_64 openwrt/19.07/x86_64 openwrt/19.07/arm_cortex-a7_neon-vfpv4 openwrt/snapshot/mipsel_24kc"

# Release Extensions
for plat in $PLAT_NAMES; do
	./scripts/release_ext.sh opcua $plat "luaclib"
	./scripts/release_ext.sh snap7 $plat "luaclib"
	./scripts/release_ext.sh plctag $plat "luaclib"
	./scripts/release_ext.sh frpc $plat "bin"
	./scripts/release_ext.sh sqlite3 $plat "raw"
done

# For pre-installed applications
mkdir __install/apps
./scripts/pre_inst.sh ioe ioe

# For ioe extensions
mkdir __install/ext

#################################
# Count the file sizes
################################
du __install -sh

###################
##
##################

if [ -f "__release/freeioe/$VERSION.tar.gz" ]
then
	rm -rf __install
	echo freeioe/$VERSION'.tar.gz already released'
	exit
fi

cd __install
tar czvf ../__release/freeioe/$VERSION.tar.gz * > /dev/null
md5sum -b ../__release/freeioe/$VERSION.tar.gz > ../__release/freeioe/$VERSION.tar.gz.md5
du ../__release/freeioe/$VERSION.tar.gz -sh
cat ../__release/freeioe/$VERSION.tar.gz.md5
## Copy to latest
cp -f ../__release/freeioe/$VERSION.tar.gz ../__release/freeioe/latest.tar.gz
cp -f ../__release/freeioe/$VERSION.tar.gz.md5 ../__release/freeioe/latest.tar.gz.md5
echo $VERSION > ../__release/freeioe/latest.version
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
rm -rf __install

# Done
echo 'May GOD with YOU always!'
