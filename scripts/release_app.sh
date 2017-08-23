
if [ $# != 3 ] ; then
	echo "Usage: release.sh <app name> <version> <git version>"
	exit 0
fi

echo "Release App:" $1

# zip files
mkdir -p __release/$1
cd ./examples/$1
echo $2 > version
echo $3 >> version

zip -r -q ../../__release/$1/$2.zip * -x *~
rm -f version
cd ../../
md5sum -b __release/$1/$2.zip > __release/$1/$2.zip.md5
du __release/$1/$2.zip -sh
cat __release/$1/$2.zip.md5
## Copy to latest
cp -f __release/$1/$2.zip __release/$1/latest.zip
cp -f __release/$1/$2.zip.md5 __release/$1/latest.zip.md5

# copy to web server folder
#mkdir -p /var/www/master/$1
#cp __release/$1.zip /var/www/master/$1/latest.zip

