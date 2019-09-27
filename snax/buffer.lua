local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local log = require 'utils.log'
local app_api = require 'app.api'

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

-- Forwarder
local listen_map = {}

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

function accept.log(ts, lvl, content, ...)
	local process, data = string.match(content, '^%[(.+)%]: (.+)$')
	if not ( process and data ) then
		return
	end

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

	for handle, srv in pairs(listen_map) do
		srv.post.on_log(list[#list])
	end
end

function accept.app_started(name, handle)
	local org_handle = nh_map[name]
	if org_handle then
		snax.self().post.app_stoped(name)
	end
	nh_map[name] = handle
end

function accept.app_event(event, name, ...)
	if event == 'start' then
		snax.self().post.app_started(name, ...)
	end
	if event == 'stop' then
		snax.self().post.app_stoped(name, ...)
	end
	-- TODO: more events?
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

function accept.listen(handle, type)
	listen_map[handle] = snax.bind(handle, type)
end

function accept.unlisten(handle, type)
	listen_map[handle] = nil
end

local function connect_log_server(enable)
	local logger = snax.queryservice('logger')
	local appmgr = snax.queryservice('appmgr')
	local obj = snax.self()
	if enable then
		logger.post.listen(obj.handle, obj.type)
		skynet.call(".logger", "lua", "listen", obj.handle, obj.type)
		appmgr.post.listen(obj.handle, obj.type, true) --- Listen on application events
	else
		logger.post.unlisten(obj.handle)
		skynet.call(".logger", "lua", "unlisten", obj.handle)
		appmgr.post.unlisten(obj.handle)
	end
end

function init()
	log.notice("::BUFFER:: System buffer service started!")
	skynet.fork(function()
		connect_log_server(true)
	end)

	skynet.fork(function()
		api = app_api:new('__COMM_DATA_LOGGER')
		api:set_handler(Handler, false)
	end)
end

function exit(...)
	connect_log_server(false)
	log.notice("::BUFFER:: System buffer service stoped!")
end
