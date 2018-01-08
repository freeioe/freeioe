# !/usr/bin/env sh

SKYNET_PLAT=$1

# Validate platform name
PLAT_NAMES="linux/amd64 lede/arm_cortex-a9_neon lede/mips_24kc lede/amd64"
PLAT_OK=0
for plat in $PLAT_NAMES; do
	if [ "$SKYNET_PLAT" == "$plat" ]; then
		PLAT_OK=1
		break
	fi
done

if [ "$SKYNET_PLAT" != "" ] && [ $PLAT_OK == 0 ]; then
	echo "Platform name your input is not valid"
	echo "   $PLAT_NAMES"
	exit 0
fi

# Release Skynet
./scripts/release_skynet.sh ~/mycode/skynet $SKYNET_PLAT

echo "--------------------------------------------"
echo "IOT System IN:" $PWD

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
mkdir -p __release/skynet_iot

# Clean up the cramfs folder
#sudo rm -rf __install
rm -rf __install
mkdir __install

# Copy files
git archive HEAD | tar -x -C __install
rm -rf __install/examples
rm -rf __install/scripts

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

# Release example (modbus)
# Release iot
./scripts/release_app.sh iot $VERSION $REVISION
./scripts/release_app.sh bms $VERSION $REVISION
./scripts/release_app.sh modbus_lua $VERSION $REVISION
./scripts/release_app.sh frpc $VERSION $REVISION
./scripts/release_opc_app.sh opcua_server $VERSION $REVISION $SKYNET_PLAT
./scripts/release_opc_app.sh opcua_client $VERSION $REVISION $SKYNET_PLAT
./scripts/release_opc_app.sh opcua_collect_example $VERSION $REVISION $SKYNET_PLAT

# For pre-installed applications
mkdir __install/apps
./scripts/pre_inst.sh iot iot $VERSION

#################################
# Count the file sizes
################################
du __install -sh

###################
##
##################
cd __install
tar czvf ../__release/skynet_iot/$VERSION.tar.gz * > /dev/null
md5sum -b ../__release/skynet_iot/$VERSION.tar.gz > ../__release/skynet_iot/$VERSION.tar.gz.md5
du ../__release/skynet_iot/$VERSION.tar.gz -sh
cat ../__release/skynet_iot/$VERSION.tar.gz.md5
## Copy to latest
cp -f ../__release/skynet_iot/$VERSION.tar.gz ../__release/skynet_iot/latest.tar.gz
cp -f ../__release/skynet_iot/$VERSION.tar.gz.md5 ../__release/skynet_iot/latest.tar.gz.md5
echo $VERSION > ../__release/skynet_iot/latest.version
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
rm -rf __install

# Done
echo 'May GOD with YOU always!'
