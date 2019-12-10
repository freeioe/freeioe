
if [ $# -lt 3 ] ; then
	echo "Usage: release_ext.sh <ext name> <platform> <type>"
	exit 0
fi

TARGET_EXT=$1

TARGET_PLAT=$2
if [ $# -lt 2 ] ; then
	TARGET_PLAT="openwrt"
fi

TARGET_TYPE=$3
if [ $# -lt 3 ] ; then
	TARGET_TYPE="luaclib"
fi

BASE_DIR=`pwd`
RELEASE_DIR="__release"
TARGET_FOLDER="bin/$TARGET_PLAT/$1"

# echo "Release Extension:" $TARGET_FOLDER

cd ./feeds/prebuild_exts/$TARGET_PLAT

### Get the version by count the commits
VERSION=`git log --oneline | wc -l | tr -d ' '`

### Generate the revision by last commit
set -- $(git log -1 --format="%ct %h")
R_SECS="$(($1 % 86400))"
R_YDAY="$(date --utc --date="@$1" "+%y.%j")"
REVISION="$(printf 'git-%s.%05d-%s' "$R_YDAY" "$R_SECS" "$2")"

# echo 'Version:'$VERSION
# echo 'Revision:'$REVISION
echo "Release Extension:" $TARGET_FOLDER "Version:" $VERSION "Revision:"$REVISION

cd $BASE_DIR

if [ -f "$RELEASE_DIR/$TARGET_FOLDER/$VERSION.tar.gz" ]
then
	echo $TARGET_FOLDER/$VERSION'.tar.gz already released'
	exit
fi

# tar gz files
mkdir -p $RELEASE_DIR/$TARGET_FOLDER
rm -rf $RELEASE_DIR/$TARGET_FOLDER/temp
mkdir -p $RELEASE_DIR/$TARGET_FOLDER/temp
echo $VERSION > $RELEASE_DIR/$TARGET_FOLDER/temp/version
echo $REVISION >> $RELEASE_DIR/$TARGET_FOLDER/temp/version

if [ "$TARGET_TYPE" == "luaclib" ] ; then
	mkdir -p $RELEASE_DIR/$TARGET_FOLDER/temp/luaclib
	cp ./feeds/prebuild_exts/$TARGET_PLAT/$TARGET_EXT.so $RELEASE_DIR/$TARGET_FOLDER/temp/luaclib/
fi
if [ "$TARGET_TYPE" == "bin" ] ; then
	mkdir -p $RELEASE_DIR/$TARGET_FOLDER/temp/bin
	cp ./feeds/prebuild_exts/$TARGET_PLAT/$TARGET_EXT $RELEASE_DIR/$TARGET_FOLDER/temp/bin/
fi
if [ "$TARGET_TYPE" == "raw" ] ; then
	cp -r ./feeds/prebuild_exts/$TARGET_PLAT/$TARGET_EXT/* $RELEASE_DIR/$TARGET_FOLDER/temp/
fi

cd $RELEASE_DIR/$TARGET_FOLDER/temp
# find . -type f |xargs -I{} file "{}"|grep "ELF\|ar "|sed 's/\(.*\):.*/\1/'|xargs $STRIP

tar czvf ../$VERSION.tar.gz * > /dev/null
md5sum -b ../$VERSION.tar.gz > ../$VERSION.tar.gz.md5
du ../$VERSION.tar.gz -sh
cat ../$VERSION.tar.gz.md5
## Copy to latest
cp -f ../$VERSION.tar.gz ../latest.tar.gz
cp -f ../$VERSION.tar.gz.md5 ../latest.tar.gz.md5
echo $VERSION > ../latest.version

cd $BASE_DIR
