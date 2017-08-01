#!/usr/bin/lua

if #arg < 1 then
	print(string.format("Usage: %s <po directory> [<file pattern>]", arg[0]))
	return
end

local source = arg[1]
local pattern = arg[2] or "*.po"

local fixup_header_order = function(path)
	assert(path)
	local f, err = io.open(path)
	if not f then
		print(err)
		return
	end

	local content = f:read('*a')
	f:close()
	content = content:gsub('(.+)("Language-Team: .+\\n"\n)(.*)("Language: .+\\n\n")(.+)', '%1%2%4%3%5')
	f, err = io.open(path, 'w+')
	if f then
		f:write(content)
		f:close()
	else
		print(err)
	end
end

local cmd = string.format("find %s -type f -name '%s'", source, pattern)

local f = io.popen(cmd)

for c in f:lines() do
	if c ~= '.' and c ~= '..' then
		local basename = c:match('.+/([^/]+)%.po$')
		local pot = source..'/templates/'..basename..'.pot'
		local ff = io.open(pot)
		if ff then
			print(string.format("Updating %-40s", c))
			local r, code, status = os.execute('msgmerge -U -N --no-wrap '..c..' '..pot);
			if not r or code ~= 'exit' then
				print(string.format('failed to merge %s', status))
			else
				fixup_header_order(c)
			end
		end
	end
end

