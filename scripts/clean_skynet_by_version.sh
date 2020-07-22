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

for item in "${!plats[@]}"; 
do
	echo "deleting ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz"
	rm ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz.md5
	rm ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz
done
