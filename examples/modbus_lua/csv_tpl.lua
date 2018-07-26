local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local packets =  {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'INPUT' then
				local input = {
					name = v[2],
					desc = v[3],
				}
				if string.len(v[4]) > 0 then
					input.vt = v[4]
				end
				input.pack = v[5]
				input.dt = v[6]
				input.saddr = v[7]
				input.rate = v[8]

				inputs[#inputs + 1] = input
			end
			if v[1] == 'PACKET' then
				local pack = {
					name = v[2],
					desc = v[3],
					func = v[4],
					saddr = v[5],
					len = v[6]
				}
				packets[#packets + 1] = pack
			end
		end
	end

	for _, pack in ipairs(packets) do
		pack.inputs = {}
		for _, input in ipairs(inputs) do
			if input.pack == pack.name then
				pack.inputs[#pack.inputs + 1] = input
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
		packets = packets
	}
end

--[[
--local cjson = require 'cjson.safe'
local tpl = load_tpl('bms')
print(cjson.encode(tpl))
]]--

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
