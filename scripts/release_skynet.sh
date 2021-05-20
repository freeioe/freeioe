# !/usr/bin/env bash

set -e

SKYNET_DIR=$1
RELEASE_DIR="$1/ioe/__release"
SKYNET_PLAT="skynet"

if [ ! -n "$2" ]
then
	SKYNET_PLAT="skynet"
else
	SKYNET_PLAT=$2"/skynet"
fi
if [ ! -n "$3" ]
then
	RELEASE_DIR="$3"
fi

RELEASE_DIR="$RELEASE_DIR/bin/$SKYNET_PLAT"

echo "--------------------------------------------"
echo "Skynet IN:" $SKYNET_DIR " PLAT:" $SKYNET_PLAT "ReleaseDir:" $RELEASE_DIR

cd $SKYNET_DIR

### Get the version by count the commits
VERSION=`git log --oneline | wc -l | tr -d ' '`

### Generate the revision by last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

echo 'Version:'$VERSION
echo 'Revision:'$REVISION

if [ -f "$RELEASE_DIR/$VERSION.tar.gz" ]
then
	echo 'skynet already released'
	exit
fi

# Clean up the cramfs folder
#sudo rm -rf __install
rm -rf __install
mkdir __install

echo $VERSION > __install/version
echo $REVISION >> __install/version

# Copy files
cp -r -L lualib __install/lualib
cp -r luaclib __install/luaclib
cp -r service __install/service
cp -r cservice __install/cservice
cp README.md __install/
cp HISTORY.md __install/
cp LICENSE __install/
cp skynet __install/
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
cd __install
mkdir -p $RELEASE_DIR
tar czvf $RELEASE_DIR/$VERSION.tar.gz * > /dev/null
md5sum -b $RELEASE_DIR/$VERSION.tar.gz > $RELEASE_DIR/$VERSION.tar.gz.md5
du $RELEASE_DIR/$VERSION.tar.gz -sh
cat $RELEASE_DIR/$VERSION.tar.gz.md5
## Copy to latest
cp -f $RELEASE_DIR/$VERSION.tar.gz $RELEASE_DIR/latest.tar.gz
cp -f $RELEASE_DIR/$VERSION.tar.gz.md5 $RELEASE_DIR/latest.tar.gz.md5
echo $VERSION > $RELEASE_DIR/latest.version
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
rm -rf __install

