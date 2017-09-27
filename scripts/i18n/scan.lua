#!/usr/bin/lua

if #arg < 1 then
	print( "Usage: "..arg[0].." <source direcory>")
end
local find_cmd = "find "..table.concat(arg).."/ -type f '(' -name '*.html' -o -name '*.lua' ')'"
local f = io.popen(find_cmd)

local stringtable = {}

local function match_translate(c)
	for key in c:gmatch([[translate%(%G*['"](.-)['"]%G*%)]]) do
		stringtable[key] = true
	end
	for key in c:gmatch([[translatef%(%G*['"](.-)['"]%G*,]]) do
		stringtable[key] = true
	end
	for key in c:gmatch("_%(%G*['\"](.-)['\"]%G*[),]*") do
		stringtable[key] = true
	end
end

for file in f:lines() do
	local ff = io.open(file)
	if ff then
		local lua_file = true 
		if string.sub(file, -4) ~= '.lua' then
			lua_file = false
		end
		for c in ff:lines() do
			if not lua_file then
				for lc in c:gmatch("{[{*%%(%[](.-)[}*%%)%]]}") do
					match_translate(lc)
				end
			else
				match_translate(c)
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
