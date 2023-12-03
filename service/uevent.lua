--[[
-- Kernel uevent msg handle service
--- Read uevent, and notify the hardware changes
--]]
local skynet = require 'skynet.manager'
local mc = require 'skynet.multicast'
local uevent_loaded, uevent = pcall(require, 'luevent')
local inspect = require 'inspect'
local log = require 'utils.logger'.new('UEVENT')

local uevent_chn = nil -- mc.new()
local uevent_msg_list = {}

local handle_uevent_msg = function(msg)
	-- local cjson = require 'cjson.safe'
	-- print(cjson.encode(msg))
	-- print(inspect(msg))
	table.insert(uevent_msg_list, msg)
end

local handle_msg = function(msg)
	if string.lower(string.sub(msg, 1, 7)) == 'libudev' then
		-- Skip libudev message
		return
	end

	local t = {}
	for w in string.gmatch(msg, "%g+") do
		t[#t + 1] = w
	end
	local t1 = t[1]
	local action, devpath = string.match(t1, "^([^@]+)@(.+)")
	local tmsg = {}
	for i, v in ipairs(t) do
		if i ~= 1 then
			local key, val = string.match(v, '(.-)=(.+)')
			tmsg[key] = val
		end
	end
	if action ~= tmsg.ACTION then
		log.error('Action diff found')
		return
	end
	if devpath ~= tmsg.DEVPATH then
		log.error('Devpath diff found')
		return
	end
	return handle_uevent_msg(tmsg)
end

local command = {}

function command.CHANNEL()
	return uevent_chn.channel
end

skynet.start(function()
	uevent_chn = mc.new()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s from session %s-%s", tostring(cmd), tostring(session), tostring(address)))
		end
	end)

	skynet.fork(function()
		if not uevent_loaded then
			log.error("luevent moduole not found!")
			return
		end

		local uevent_conn = uevent.new(function(msg)
			return handle_msg(msg)
		end)

		while true do
			local r, err = uevent_conn:run()
			if not r then
				log.error(err)
			end
			if #uevent_msg_list > 0 then
				for _, v in ipairs(uevent_msg_list) do
					uevent_chn:publish(v)
				end
				uevent_msg_list = {}
			end
			skynet.sleep(5)
		end
	end)

	skynet.register ".uevent"
end)
