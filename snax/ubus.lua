local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ubus = require 'ubus'
local crypt = require 'skynet.crypt'
local log = require 'utils.log'
local app_api = require 'app.api'

local api = nil
local bus = nil

local handle_to_process = function(handle)
	return string.format("%08x", handle)
end

--[[
-- Api Handler
--]]
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")
		local content = crypt.base64encode(table.concat({...}, '\t'))
		local list  = comm_buffer[app] or {}
		list[#list + 1] = {
			sn = sn,
			dir = dir,
			ts = ts,
			data = content
		}
		if #list > max_comm_buf_size then
			table.remove(list, 1)
		end
		comm_buffer[app] = list

		for handle, srv in pairs(listen_map) do
			srv.post.on_comm(list[#list])
		end
	end,
	on_event = function(app, sn, level, type_, info, data, timestamp)
		event_buffer[#event_buffer + 1] = {
			app = app,
			sn = sn,
			level = level,
			['type'] = type_,
			info = info,
			data = data,
			timestamp = timestamp,
		}
		if #event_buffer > max_event_buf_size then
			table.remove(event_buffer, 1)
		end

		for handle, srv in pairs(listen_map) do
			srv.post.on_event(event_buffer[#event_buffer])
		end
	end,
}

function response.ping()
	return "PONG"
end

function response.create_object(name, methods)
	return false
end

function response.delete_object(name)
	return false
end

function accept.publish(name, data)
end

function init()
	--[[
	local sysinfo = require 'utils.sysinfo'
	if sysinfo.os_id() ~= 'openwrt' then
		log.notice("System ubus service can only run on OpenWRT")
		skynet.fork(function()
			snax.exit()
		end)
	end
	]]--
	bus = ubus:new()
	bus:connect("172.30.19.103", 11000)
	print(bus:status())
	print('add object', bus:add('freeioe', {
		ping = { 
			function()
				print('on ping')
				return 0
			end, { id = ubus.INT32, msg = ubus.STRING }
		},
		test = {
			function(req, msg)
				print('on test')
			end, { id = ubus.INT32, msg = ubus.STRING }
		}
	}, function(...)
		print('subscribe cb', ...)
	end))

	log.notice("System ubus service started!")
end

function exit(...)
	log.notice("System ubus service stoped!")
end
