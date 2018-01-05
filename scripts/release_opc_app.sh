
if [ $# -lt 3 ] ; then
	echo "Usage: release_opc_app.sh <app name> <version> <git version>"
	exit 0
fi

TARGET_PLAT=$4
if [ $# -lt 4 ] ; then
	TARGET_PLAT="openwrt"
fi

TARGET_FOLDER=$1_$TARGET_PLAT

echo "Release App:" $TARGET_FOLDER

if [ -f "__release/$TARGET_FOLDER/$2.zip" ]
then
	echo $TARGET_FOLDER/$2'.zip already released'
	exit
fi

# zip files
mkdir -p __release/$TARGET_FOLDER
cd ./examples/$1
echo $2 > version
echo $3 >> version

# for so linked
mv luaclib/opcua.so ./opcua.so.bak~
cp ../../prebuild/$TARGET_PLAT/opcua.so luaclib/opcua.so

zip -r -q ../../__release/$TARGET_FOLDER/$2.zip * -x *~
rm -f version
rm -f luaclib/opcua.so
mv ./opcua.so.bak~ luaclib/opcua.so
cd ../../
md5sum -b __release/$TARGET_FOLDER/$2.zip > __release/$TARGET_FOLDER/$2.zip.md5
du __release/$TARGET_FOLDER/$2.zip -sh
cat __release/$TARGET_FOLDER/$2.zip.md5
## Copy to latest
cp -f __release/$TARGET_FOLDER/$2.zip __release/$TARGET_FOLDER/latest.zip
cp -f __release/$TARGET_FOLDER/$2.zip.md5 __release/$TARGET_FOLDER/latest.zip.md5
echo $2 > __release/$TARGET_FOLDER/latest.version

# copy to web server folder
#mkdir -p /var/www/master/$TARGET_FOLDER
#cp __release/$TARGET_FOLDER.zip /var/www/master/$TARGET_FOLDER/latest.zip

