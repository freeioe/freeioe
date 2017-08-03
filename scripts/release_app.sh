
if [ $# != 2 ] ; then
	echo "Usage: release.sh <app name> <version>"
	exit 0
fi

# zip files
mkdir -p __release/$1
cd ./examples/$1
zip -r -q ../../__release/$1/ver_$2.zip * -x *~
cd ../../

# copy to web server folder
#mkdir -p /var/www/master/$1
#cp __release/$1.zip /var/www/master/$1/latest.zip

