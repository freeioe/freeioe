#!/bin/sh
#
# Code Backup Script
# Creates a backup archive of the current codebase from git master branch
#
# Usage: code_backup.sh
#
# Output:
#   Creates __release/code.tar.gz containing the archived code
#
# Process:
#   1. Creates temporary backup directory
#   2. Exports git master branch to backup
#   3. Creates compressed tarball
#   4. Cleans up temporary directory
#

# Create backup and release directories
mkdir -p __backup
mkdir -p __release

# Export git master branch to backup directory
git archive master | tar -x -C __backup

# Create compressed archive
tar -zcf __release/code.tar.gz __backup

# Clean up temporary directory
rm -rf __backup
