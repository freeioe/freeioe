# !/usr/bin/env sh

SKYNET_DIR=$1
SKYNET_PLAT="skynet"

if [ ! -n "$2" ]
then
	SKYNET_PLAT="skynet"
else
	SKYNET_PLAT=$2"_skynet"
fi

echo "--------------------------------------------"
echo "Skynet IN:" $SKYNET_DIR " PLAT:" $SKYNET_PLAT

cd $SKYNET_DIR

# Clean up the cramfs folder
#sudo rm -rf __install
rm -rf __install
mkdir __install

# Copy files
cp -r lualib __install/lualib
cp -r luaclib __install/luaclib
cp -r service __install/service
cp -r cservice __install/cservice
cp README.md __install/
cp HISTORY.md __install/
cp LICENSE __install/
cp skynet __install/
cd __install/
ln -s ../skynet_iot ./iot
ln -s /var/log ./logs
cd - > /dev/null

### Get the version by count the commits
VERSION=`git log --oneline | wc -l | tr -d ' '`

### Generate the revision by last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

echo 'Version:'$VERSION
echo 'Revision:'$REVISION
echo $VERSION > __install/version
echo $REVISION >> __install/version

# Compile lua files
# ./scripts/compile_lua.sh 

#################################
# Count the file sizes
################################
du __install -sh

###################
##
##################
cd __install
mkdir -p ../iot/__release/$SKYNET_PLAT
tar czvf ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz * > /dev/null
md5sum -b ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz > ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz.md5
du ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz -sh
cat ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz.md5
## Copy to latest
cp -f ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz ../iot/__release/$SKYNET_PLAT/latest.tar.gz
cp -f ../iot/__release/$SKYNET_PLAT/$VERSION.tar.gz.md5 ../iot/__release/$SKYNET_PLAT/latest.tar.gz.md5
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
rm -rf __install

