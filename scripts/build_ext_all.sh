#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

BUILD_LIB=$1
CUR_DIR=`pwd`

# Get all platforms
source $SCRIPTPATH/plats.sh

for item in "${!plats[@]}"; 
do
	if [ "$BUILD_LIB" == "opcua" ]; then
		bash $SCRIPTPATH/build_ext_opcua.sh $item ${plats[$item]} $CUR_DIR/../..
	fi
	mkdir -p $SCRIPTPATH/../feeds/prebuild_exts/$item/
	bash $SCRIPTPATH/build_ext.sh $item ${plats[$item]} $SCRIPTPATH/../feeds/prebuild_exts/$item/
done
