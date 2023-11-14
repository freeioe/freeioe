#!/usr/bin/env bash

declare -A plats

plats["linux/x86_64"]="native"
plats["linux/htnice_2022.02.6/aarch64"]="htnice_gt675x.sh"
# plats["openwrt/14.07/mipsel_24kc"]="bmr200.sh"

plats["openwrt/17.01/arm_cortex-a9_neon"]="tgw3030_exports.sh"
# plats["openwrt/17.01/arm_cortex-a7_neon_gcc"]="mdm9607_exports.sh"

# plats["openwrt/18.06/mips_24kc"]="mips_24kc.sh"
# plats["openwrt/18.06/x86_64"]="x86_64_glibc_18.06.sh"

plats["openwrt/19.07/arm_cortex-a9_neon"]="imx6_19.07.sh"
plats["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_19.07.sh"
plats["openwrt/19.07/x86_64"]="x86_64_glibc_19.07.sh"

## 21.02
plats["openwrt/21.02/aarch64_cortex-a72"]="brcm_a72_21.02.sh"
plats["openwrt/21.02/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_21.02.sh"
plats["openwrt/21.02/mipsel_24kc"]="ramips_mt76x8_21.02.sh"

## 22.03
plats["openwrt/22.03/aarch64_generic"]="aarch64_generic_22.03.sh"
# plats["openwrt/22.03/arm_arm926ej-s"]="nuc980_arm926ej-s.sh"

## 23.05
plats["openwrt/23.05/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_23.05.sh"

## openwrt master
plats["openwrt/snapshot/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_snapshot.sh"
plats["openwrt/snapshot/aarch64_generic"]="aarch64_generic_snapshot.sh"
# plats["openwrt/snapshot/aarch64_cortex-a53"]="sunxi_a53_snapshot.sh"
plats["openwrt/snapshot/mipsel_24kc"]="ramips_mt76x8_snapshot.sh"

# plats["android/arm"]="android_arm.sh"
