#!/bin/sh
#
# Compile Lua Scripts
# Compiles all .lua files in __install directory to bytecode
#
# Usage: compile_lua.sh
#
# Process:
#   1. Changes to __install directory
#   2. Compiles all .lua files to .luac bytecode using luac
#   3. Renames .lua.luac files back to .lua (replacing source)
#   4. Makes start.lua and run.lua executable
#
# Notes:
#   - Must be run from project root (expects __install directory)
#   - Original .lua files are replaced with compiled bytecode
#

cd __install || exit 1

# Compile all .lua files to bytecode
find ./ -name "*.lua" -exec luac -o {}.luac {} \;

# Replace .lua files with compiled bytecode (.lua.luac -> .lua)
for file in $(find ./ -type f -name "*.lua.luac"); do
    mv "$file" "${file%.lua.luac}.lua"
done

# Make entry point scripts executable
find ./ -name "start.lua" -exec chmod a+x {} \;
find ./ -name "run.lua" -exec chmod a+x {} \;

cd ..
