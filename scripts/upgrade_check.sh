#!/bin/sh
# Check if FreeIOE and Skynet versions are compatible

FREEIOE_PATH=$1
SKYNET_PATH=$2

. ${FREEIOE_PATH}/scripts/functions.sh

# Get FreeIOE version
set -- $(read_version "${FREEIOE_PATH}/version")
fver=$1
fbranch=$2

# Get Skynet version
set -- $(read_version "${SKYNET_PATH}/version")
sver=$1
sbranch=$2

# FreeIOE > 1609 requires Skynet >= 2547 (for @path config support)
if [ "$fver" -gt 1609 ] && [ "$sver" -lt 2547 ]; then
	if [ ! -f "${FREEIOE_PATH}/config.path.compat" ]; then
		exit 1
	fi
	mv ${FREEIOE_PATH}/config.path.compat ${FREEIOE_PATH}/config.path
fi

exit 0
