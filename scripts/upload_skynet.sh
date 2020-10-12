#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

VERSION=$1
echo $VERSION

RELEASE_DIR=$SCRIPTPATH/../__release/bin

# Get all platforms
source $SCRIPTPATH/plats.sh

mkdir -p /tmp/__kooiot_openwrt_upload/bin

for item in "${!plats[@]}"; 
do
	ls -lh ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz

	mkdir -p /tmp/__kooiot_openwrt_upload/bin/${item}/skynet/

	cp -p ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz* /tmp/__kooiot_openwrt_upload/bin/${item}/skynet/

	ls -lh /tmp/__kooiot_openwrt_upload/bin/${item}/skynet/${VERSION}.tar.gz
done

scp -rp /tmp/__kooiot_openwrt_upload/bin kooiot.com:/var/www/openwrt/download/

rm -rf /tmp/__kooiot_openwrt_upload
