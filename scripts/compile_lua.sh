cd __install

find ./ -name "*.lua" -exec luac -o {}.luac {} \;

for file in $(find ./ -type f -name "*.lua.luac"); do mv $file ${file%.lua.luac}.lua; done

find ./ -name "start.lua" -exec chmod a+x {} \;
find ./ -name "run.lua" -exec chmod a+x {} \;

cd ..
