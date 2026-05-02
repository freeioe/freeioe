#!/usr/bin/env bash
#
# Platform Definitions
# Defines all supported platforms and their corresponding toolchain scripts
#
# Usage: source scripts/plats.sh
#
# Structure:
#   plats["<platform>"] = "<toolchain_script>"
#
# Where:
#   - platform: Format is "<distro>/<version>/<architecture>"
#   - toolchain_script: Name of toolchain setup script in ~/toolchains/
#
# Platform Format:
#   - linux/x86_64: Native Linux builds
#   - openwrt/<version>/<arch>: OpenWrt cross-compilation
#
# Examples:
#   source scripts/plats.sh
#   echo "${plats[openwrt/19.07/arm_cortex-a7_neon-vfpv4]}"
#

# Declare associative array for platform definitions
declare -A plats

# ============================================================================
# Native Platforms
# ============================================================================

# Native x86_64 Linux build (no cross-compilation)
plats["linux/x86_64"]="native"

# Htnice ARM64 platform
plats["linux/htnice_2022.02.6/aarch64"]="htnice_gt675x.sh"

# ============================================================================
# OpenWrt 17.01
# ============================================================================

plats["openwrt/17.01/arm_cortex-a9_neon"]="tgw3030_exports.sh"

# ============================================================================
# OpenWrt 19.07
# ============================================================================

plats["openwrt/19.07/arm_cortex-a9_neon"]="imx6_19.07.sh"
plats["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_19.07.sh"
plats["openwrt/19.07/x86_64"]="x86_64_glibc_19.07.sh"

# ============================================================================
# OpenWrt 21.02
# ============================================================================

plats["openwrt/21.02/aarch64_cortex-a72"]="brcm_a72_21.02.sh"
plats["openwrt/21.02/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_21.02.sh"
plats["openwrt/21.02/mipsel_24kc"]="ramips_mt76x8_21.02.sh"

# ============================================================================
# OpenWrt 22.03
# ============================================================================

plats["openwrt/22.03/aarch64_generic"]="aarch64_generic_22.03.sh"

# ============================================================================
# OpenWrt 24.10
# ============================================================================

plats["openwrt/24.10/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_24.10.sh"

# ============================================================================
# OpenWrt 25.12
# ============================================================================

plats["openwrt/25.12/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_25.12.sh"

# ============================================================================
# OpenWrt Snapshot (Master)
# ============================================================================

plats["openwrt/snapshot/arm_cortex-a7_neon-vfpv4"]="sunxi_a7_snapshot.sh"
plats["openwrt/snapshot/aarch64_generic"]="aarch64_generic_snapshot.sh"
plats["openwrt/snapshot/mipsel_24kc"]="ramips_mt76x8_snapshot.sh"
