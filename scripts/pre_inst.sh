#!/usr/bin/env bash
#
# Pre-install Application
# Installs an application into the __install directory for release packaging
#
# Usage: pre_inst.sh <app_name> <inst_name>
#
# Arguments:
#   app_name  - Name of the application in __release (e.g., example_apps/ioe)
#   inst_name - Instance name for the installed app (e.g., ioe)
#
# Process:
#   1. Creates destination directory in __install/apps/<inst_name>
#   2. Extracts application from __release/<app_name>/latest.zip
#   3. Application is ready to be included in release tarball
#
# Examples:
#   pre_inst.sh example_apps/ioe ioe
#

set -e

# Validate arguments
if [ $# != 2 ] ; then
	echo "Usage: pre_inst.sh <app name> <inst name>"
	exit 0
fi

# Create destination directory
mkdir -p __install/apps/"$2"

# Extract application from release archive
unzip -q __release/"$1"/latest.zip -d __install/apps/"$2"

# Echo information to apps/_list file
# echo "NAME='"$1"' INSNAME='"$1"' APPJSON='{\"name\":\"$1\",\"desc\":\"EMBEDDED\",\"type\":\"app\",\"author\":\""$2"\",\"path\":\""$2"\\/"$1"\",\"depends\":{},\"version\":\""$3"\"}'" >> __install/apps/_list

