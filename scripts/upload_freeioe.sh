#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

VERSION=$1
echo $VERSION

RELEASE_DIR=$SCRIPTPATH/../__release

mkdir -p /tmp/__kooiot_openwrt_upload/freeioe
cp -p ${RELEASE_DIR}/freeioe/${VERSION}.tar.gz* /tmp/__kooiot_openwrt_upload/freeioe/


scp -rp /tmp/__kooiot_openwrt_upload/freeioe kooiot.com:/var/www/openwrt/download/

rm -rf /tmp/__kooiot_openwrt_upload/freeioe
