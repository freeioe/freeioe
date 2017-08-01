
if [ $# != 1 ] ; then
	echo "Usage: release.sh <app name>"
	exit 0
fi

# zip files
cd ./examples/$1
zip -r -q ../../__release/$1.zip * -x debug~
cd ../../

# copy to web server folder
#mkdir -p /var/www/master/$1
#cp __release/$1.zip /var/www/master/$1/latest.zip

