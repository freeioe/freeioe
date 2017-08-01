#!/usr/bin/lua

if #arg < 1 then
	print( "Usage: "..arg[0].." <source direcory>")
end
local find_cmd = "find "..table.concat(arg).." -type f '(' -name '*.html' -o -name '*.lua' ')'"
local f = io.popen(find_cmd)

local stringtable = {}
for c in f:lines() do
	local ff = io.open(c)
	if ff then
		for c in ff:lines() do
			for key in c:gmatch([[translate%(%G*['"](.-)['"]%G*%)]]) do
				stringtable[key] = true
			end
			for key in c:gmatch([[_%(%G*['"](.-)['"]%G*%)]]) do
				stringtable[key] = true
			end
			for key in c:gmatch([[translatef%(%G*['"](.-)['"]%G*,]]) do
				stringtable[key] = true
			end
		end
		ff:close()
	end
end

f:close()

print("msgid \"\"\nmsgstr \"Content-Type: text/plain; charset=UTF-8\"\n\n")

local sort_table = {}
for key, _ in pairs(stringtable) do
	sort_table[#sort_table + 1] = key
end
table.sort(sort_table)

for _, key in pairs(sort_table) do
	if key:len() > 0 then
		print(string.format('msgid \"%s\"\nmsgstr \"\"\n\n', key))
	end
end
