#!/usr/bin/env bash

declare -A plats

plats["linux/x86_64"]="native"
plats["openwrt/17.01/arm_cortex-a9_neon"]="tg3030_exports.sh"
plats["openwrt/17.01/arm_cortex-a7_neon_gcc"]="mdm9607_exports.sh"

plats["openwrt/18.06/mips_24kc"]="mips_24kc.sh"
plats["openwrt/18.06/x86_64"]="x86_64_glibc_18.06.sh"

plats["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_19.07.sh"
plats["openwrt/19.07/x86_64"]="x86_64_glibc_19.07.sh"

## openwrt master
plats["openwrt/snapshot/aarch64_cortex-a53"]="sunxi_a53_snapshot.sh"
plats["openwrt/snapshot/mipsel_24kc"]="ramips_mt76x8_snapshot.sh"

# plats["android/arm"]="android_arm.sh"
