# !/usr/bin/env sh

cd $1

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
cd -

# copy lwf files

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

###################
##
##################
cd __install
find . -name '*~' -ok rm -f {} \;
tar czvf ../iot/__release/skynet-1.0.tar.gz * > /dev/null
cd - > /dev/null

# Clean up the rootfs files
#sudo rm -rf __install
rm -rf __install

