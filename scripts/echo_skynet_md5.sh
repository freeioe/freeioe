#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

VERSION=$1
echo $VERSION

RELEASE_DIR=$SCRIPTPATH/../__release/bin

declare -A plats

plats["linux/x86_64"]="native"
plats["openwrt/17.01/arm_cortex-a9_neon"]="imx6_exports.sh"
plats["openwrt/18.06/mips_24kc"]="mips_24kc.sh"
plats["openwrt/18.06/x86_64"]="x86_64_glibc.sh"
# plats["openwrt/aarch64_cortex-a53"]="bp3plus_exports.sh"
plats["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="sunxi_a7.sh"

for item in "${!plats[@]}"; 
do
	cat ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz.md5
	ls -l ${RELEASE_DIR}/${item}/skynet/${VERSION}.tar.gz
done
