
if [ $# != 3 ] ; then
	echo "Usage: pre_inst.sh <app name> <inst name> <version>"
	exit 0
fi

# copy files
cp -r ./examples/$1 __install/apps/
rm -f __install/apps/$1/debug~

# echo "NAME='"$1"' INSNAME='"$1"' APPJSON='{\"name\":\"$1\",\"desc\":\"EMBEDDED\",\"type\":\"app\",\"author\":\""$2"\",\"path\":\""$2"\\/"$1"\",\"depends\":{},\"version\":\""$3"\"}'" >> __install/apps/_list
