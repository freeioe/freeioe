#!/usr/bin/env bash

set -e

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

SKYNET_DIR=`pwd`

# Get all platforms
source $SCRIPTPATH/plats.sh

for item in "${!plats[@]}"; 
do
	bash $SCRIPTPATH/build_skynet.sh $item ${plats[$item]} $SKYNET_DIR $SCRIPTPATH/../
done
