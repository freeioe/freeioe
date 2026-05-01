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

echo "Upgrade checking... FreeIOE ver:$fver Skynet ver:$sver"
# FreeIOE > 1609 requires Skynet >= 2547 (for @path config support)
if [ "$fver" -gt 1609 ] && [ "$sver" -lt 2547 ]; then
	if [ -f "${FREEIOE_PATH}/config.path.compat" ]; then
		# Backup existing config.path if present
		if [ -f "${FREEIOE_PATH}/config.path" ]; then
			backup_file="${FREEIOE_PATH}/config.path.backup"
			echo "Backing up existing config.path to: $(basename "$backup_file")"
			mv "${FREEIOE_PATH}/config.path" "$backup_file"
			if [ $? -ne 0 ]; then
				echo "Failed to backup config.path"
			fi
		fi

		echo "Use FreeIOE config.path.compat"
		mv "${FREEIOE_PATH}/config.path.compat" "${FREEIOE_PATH}/config.path"
		if [ $? -ne 0 ]; then
			echo "Failed to move config.path.compat to config.path"
			exit 1 # failed here to reject upgrade thus trigger rollback??
		fi
	fi
fi

echo "FreeIOE upgrade check done"
exit 0
