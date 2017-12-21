
if [ $# != 4 ] ; then
	echo "Usage: release_opc_app.sh <app name> <version> <git version> <platform>"
	exit 0
fi

echo "Release App:" $1

# zip files
mkdir -p __release/$1
cd ./examples/$1
echo $2 > version
echo $3 >> version

# for so linked
mv luaclib/opcua.so ./opcua.so.bak~
cp ../../prebuild/$4/opcua.so luaclib/opcua.so

zip -r -q ../../__release/$1_$4/$2.zip * -x *~
rm -f version
rm -f luaclib/opcua.so
mv ./opcua.so.bak~ luaclib/opcua.so
cd ../../
md5sum -b __release/$1/$2.zip > __release/$1/$2.zip.md5
du __release/$1/$2.zip -sh
cat __release/$1/$2.zip.md5
## Copy to latest
cp -f __release/$1/$2.zip __release/$1/latest.zip
cp -f __release/$1/$2.zip.md5 __release/$1/latest.zip.md5
echo $2 > __release/$1/latest.version

# copy to web server folder
#mkdir -p /var/www/master/$1
#cp __release/$1.zip /var/www/master/$1/latest.zip

