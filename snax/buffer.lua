local skynet = require 'skynet'
local snax = require 'skynet.snax'
local socket = require 'skynet.socket'
local crypt = require 'skynet.crypt'
local log = require 'utils.log'
local app_api = require 'app.api'
local cyclebuffer = require 'cyclebuffer'
local cjson = require 'cjson.safe'

local api = nil

-- Communication Data
local comm_buffer = {}
local max_comm_buf_size = 256

-- Log Data
local nh_map = {} -- name handle map
local log_buffer = {}
local max_log_buf_size = 256
local handle_to_process = function(handle)
	return string.format("%08x", handle)
end

-- Event Data
local event_buffer = {}
local max_event_buf_size = 256

-- UDP Forwarder
local udp = nil
local udp_target = nil

--[[
-- Api Handler
--]]
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		local hex = crypt.hexencode(table.concat({...}, '\t'))
		hex = string.gsub(hex, "%w%w", "%1 ")
		local list  = comm_buffer[app] or {}
		list[#list + 1] = {
			sn = sn,
			dir = dir,
			ts = ts,
			data = hex
		}
		if #list > max_comm_buf_size then
			table.remove(list, 1)
		end
		comm_buffer[app] = list
		if udp and udp_target then
			socket.sendto(udp, udp_target, cjson.encode({
				['type'] = 'comm',
				data = list[#list]
			}))
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
		if udp and udp_target then
			socket.sendto(udp, udp_target, cjson.encode({
				['type'] = 'event',
				data = event_buffer[#event_buffer]
			}))
		end
	end,
}

function response.ping()
	return "PONG"
end

function response.get_comm(app)
	if not app then
		return comm_buffer
	end
	return comm_buffer[app]
end

function response.get_log(app)
	if not app then
		return log_buffer
	end
	local handle = nh_map[app]
	if not handle then
		return nil, "Application is not running"
	end
	local process = handle_to_process(handle)
	return log_buffer[process]
end

function response.get_event()
	return event_buffer
end

local function close_udp()
	if udp then
		socket.close(udp)
		udp = nil
		udp_target = nil
	end
end

function response.start_forward()
	close_udp()
	log.notice("UDP Forward is starting...")
	udp = socket.udp(function(str, from) 
		--print(str, from)
		if str == 'WHOISYOURDADDY' then
			udp_target = from
		else
			socket.sendto(udp, from, str)
		end
	end, '0.0.0.0', 7788)
end

function response.stop_forward()
	close_udp()
end

function accept.log(ts, lvl, content, ...)
	local process, data = string.match(content, '^%[(.+)%]: (.+)$')
	local list = log_buffer[process] or {}
	list[#list + 1] = {
		timestamp = ts,
		level = lvl,
		process = process,
		content = data
	}
	if #list > max_log_buf_size then
		table.remove(list, 1)
	end
	log_buffer[process] = list

	if udp and udp_target then
		socket.sendto(udp, udp_target, cjson.encode({
			['type'] = 'log',
			data = list[#list]
		}))
	end
end

function accept.app_started(name, handle)
	local org_handle = nh_map[name]
	if org_handle then
		accept.app_stoped(name)
	end
	nh_map[name] = handle
end

function accept.app_stoped(name)
	local handle = nh_map[name]
	if not handle then
		return
	end
	local process = handle_to_process(handle)
	log_buffer[process] = nil
	nh_map[name] = nil
end

function accept.app_list(list)
	for k, v in pairs(list) do
		if v.inst then
			nh_map[k] = v.inst.handle
		end
	end
end

local function connect_log_server(enable)
	local logger = snax.uniqueservice('logger')
	local appmgr = snax.uniqueservice('appmgr')
	local obj = snax.self()
	if enable then
		logger.post.reg_snax(obj.handle, obj.type)
		--skynet.call(".logger", "lua", "reg_snax", obj.handle, obj.type)
		appmgr.post.reg_snax(obj.handle, obj.type)
	else
		logger.post.unreg_snax(obj.handle)
		--skynet.call(".logger", "lua", "unreg_snax", obj.handle)
		appmgr.post.unreg_snax(obj.handle)
	end
end

function init()
	log.notice("System buffer service started!")
	skynet.fork(function()
		connect_log_server(true)
	end)

	skynet.fork(function()
		api = app_api:new('__COMM_DATA_LOGGER')
		api:set_handler(Handler, false)
	end)
end

function exit(...)
	log.notice("System buffer service stoped!")
end
