#!/usr/bin/env sh
#
# Cleanup Code Editor Backup Files
# Removes backup files created by text editors (~ files)
#
# Usage: cleanup_code.sh
#
# Process:
#   Finds and removes all files ending with '~' (backup files)
#   These are typically created by editors like emacs, vim, etc.
#
# Files removed:
#   - *~ (editor backup files)
#
# Example:
#   cleanup_code.sh
#

find . -name "*~" | xargs rm -f
