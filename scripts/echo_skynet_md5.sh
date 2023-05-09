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

rm -f ./MD5SUM

for item in "${!plats[@]}"; 
do
	MD5SUM="$(cat ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz.md5 | awk '{print $1}')"
	ls -lh ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz

	VER="$(echo ${item} | awk -F/ '{print $2}')"
	ARCH="$(echo ${item} | awk -F/ '{print $3}')"
	echo $MD5SUM" "${VER}" "${ARCH} >> ./MD5SUM
done
