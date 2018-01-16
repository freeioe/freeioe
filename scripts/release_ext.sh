
if [ $# -lt 3 ] ; then
	echo "Usage: release_opc_app.sh <app name> <version> <git version>"
	exit 0
fi

TARGET_PLAT=$4
if [ $# -lt 4 ] ; then
	TARGET_PLAT="openwrt"
fi

TARGET_TYPE=$5
if [ $# -lt 5 ] ; then
	TARGET_TYPE="luaclib"
fi

TARGET_FOLDER="ext/$TARGET_PLAT/$1"

echo "Release Extension:" $TARGET_FOLDER

if [ -f "__release/$TARGET_FOLDER/$2.tar.gz" ]
then
	echo $TARGET_FOLDER/$2'.tar.gz already released'
	exit
fi

# tar gz files
mkdir -p __release/$TARGET_FOLDER
mkdir -p __release/$TARGET_FOLDER/temp
echo $2 > __release/$TARGET_FOLDER/temp/version
echo $3 > __release/$TARGET_FOLDER/temp/version

if [ "$TARGET_TYPE" == "luaclib" ] ; then
	mkdir -p __release/$TARGET_FOLDER/temp/luaclib
	cp ./prebuild/$TARGET_PLAT/$1.so __release/$TARGET_FOLDER/temp/luaclib/
fi
if [ "$TARGET_TYPE" == "bin" ] ; then
	mkdir -p __release/$TARGET_FOLDER/temp/bin
	cp ./prebuild/$TARGET_PLAT/$1 __release/$TARGET_FOLDER/temp/bin/
fi

cd __release/$TARGET_FOLDER/temp

tar czvf ../$2.tar.gz * > /dev/null
md5sum -b ../$2.tar.gz > ../$2.tar.gz.md5
du ../$2.tar.gz -sh
cat ../$2.tar.gz.md5
## Copy to latest
cp -f ../$2.tar.gz ../latest.tar.gz
cp -f ../$2.tar.gz.md5 ../latest.tar.gz.md5
echo $2 > ../latest.version

cd -
