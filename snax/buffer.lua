---
-- Buffer Service - Manages communication, log, and event data buffers
--
-- Features:
-- - Circular buffers for comm, log, and event data with configurable max sizes
-- - Real-time forwarding to registered listeners via callbacks
-- - Automatic buffer management to prevent memory leaks
-- - Integration with app_api for data logging
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local app_api = require 'app.api'

-- ============================================================================
-- Constants
-- ============================================================================

local DEFAULT_BUFFER_SIZE = 256
local BUFFER_SHRINK_THRESHOLD = 64  -- Shrink buffer when below this size
local BUFFER_CHECK_INTERVAL = 60000 -- Check buffer size every 60 seconds
local LOG_LISTEN_INTERVAL = 50      -- Log buffer fire interval (ms)

-- ============================================================================
-- Module State
-- ============================================================================

local api = nil
local log = nil

-- Communication Data Buffer
local comm_buffer = {}
local max_comm_buf_size = DEFAULT_BUFFER_SIZE

-- Log Data Buffer
local nh_map = {} -- name handle map
local log_buffer = {}
local max_log_buf_size = DEFAULT_BUFFER_SIZE

-- Event Data Buffer
local event_buffer = {}
local max_event_buf_size = DEFAULT_BUFFER_SIZE

-- Listener Registry
local listen_map = {}

-- ============================================================================
-- Utility Functions
-- ============================================================================

---
-- Convert handle to process string with caching
-- @param handle: numeric handle value
-- @return: formatted process string (e.g., "00001234")
---
local function handle_to_process(handle)
	assert(handle, 'handle is nil')
	return string.format("%08x", handle)
end

---
-- Manage buffer size to prevent unbounded growth
-- @param buffer: the buffer table
-- @param max_size: maximum allowed size
-- @return: trimmed buffer if necessary
---
local function manage_buffer_size(buffer, max_size)
	if #buffer <= max_size then
		return buffer
	end

	-- Remove oldest entries to maintain max_size
	local remove_count = #buffer - max_size
	for i = 1, remove_count do
		table.remove(buffer, 1)
	end

	return buffer
end

-- ============================================================================
-- API Handlers
-- ============================================================================

---
-- API Handler for communication and event data
-- Handles incoming data from applications and forwards to listeners
---
local Handler = {
	---
	-- Handle communication data from applications
	-- @param app: application name
	-- @param sn: serial number
	-- @param dir: communication direction
	-- @param ts: timestamp
	-- @param ...: variable arguments (communication data)
	---
	on_comm = function(app, sn, dir, ts, ...)
		assert(app, 'app is nil')
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")

		local content = crypt.base64encode(table.concat({...}, '\t'))
		local list = comm_buffer[app] or {}
		list[#list + 1] = {
			sn = sn,
			dir = dir,
			ts = ts,
			data = content
		}

		list = manage_buffer_size(list, max_comm_buf_size)
		comm_buffer[app] = list

		-- Forward to all registered listeners
		for handle, srv in pairs(listen_map) do
			srv.port.on_comm(list[#list])
		end
	end,

	---
	-- Handle event data from applications
	-- @param app: application name
	-- @param sn: serial number
	-- @param level: event level
	-- @param type_: event type
	-- @param info: event info
	-- @param data: event data
	-- @param timestamp: event timestamp
	---
	on_event = function(app, sn, level, type_, info, data, timestamp)
		if not app then
			log:warning("on_event: app is nil")
			return
		end

		event_buffer[#event_buffer + 1] = {
			app = app,
			sn = sn,
			level = level,
			['type'] = type_,
			info = info,
			data = data,
			timestamp = timestamp,
		}

		event_buffer = manage_buffer_size(event_buffer, max_event_buf_size)

		-- Forward to all registered listeners
		for handle, srv in pairs(listen_map) do
			srv.post.on_event(event_buffer[#event_buffer])
		end
	end,
}

-- ============================================================================
-- Response Handlers
-- ============================================================================

---
-- Ping handler for health check
-- @return: "PONG"
---
function response.ping()
	return "PONG"
end

---
-- Get communication buffer data
-- @param app: application name (nil returns all apps)
-- @return: buffer data or error message
---
function response.get_comm(app)
	if app == nil then
		return comm_buffer
	end

	return comm_buffer[app]
end

---
-- Get log buffer data
-- @param app: application name (nil returns all logs)
-- @return: buffer data or error message
---
function response.get_log(app)
	if app == nil then
		return log_buffer
	end

	local handle = nh_map[app]
	if not handle then
		return nil, "Application is not running"
	end

	local process = handle_to_process(handle)

	return log_buffer[process] or {}
end

---
-- Get event buffer data
-- @return: event buffer data
---
function response.get_event()
	return event_buffer
end

-- ============================================================================
-- Accept Handlers
-- ============================================================================

---
-- Handle log messages from logger service
-- @param ts: timestamp
-- @param lvl: log level
-- @param content: log content with format "[process]: message"
-- @param ...: additional arguments
---
function accept.log(ts, lvl, content, ...)
	if type(content) ~= 'string' then
		return
	end

	local process, data = string.match(content, '^%[(.+)%]: (.+)$')
	if not process or not data then
		log:trace("Log format mismatch, content:", content)
		return
	end

	-- Validate process format
	if not process:match('^%w+$') then
		log:warning("Invalid process name in log:", process)
		return
	end

	local list = log_buffer[process] or {}
	list[#list + 1] = {
		timestamp = ts,
		level = lvl,
		process = process,
		content = data
	}

	list = manage_buffer_size(list, max_log_buf_size)
	log_buffer[process] = list

	-- Forward to all registered listeners
	for handle, srv in pairs(listen_map) do
		srv.post.on_log(list[#list])
	end
end

---
-- Handle application started event
-- @param name: application name
-- @param handle: application service handle
---
function accept.app_started(name, handle)
	assert(name, 'app name is nil')

	-- Clean up old handle if exists
	local org_handle = nh_map[name]
	if org_handle then
		snax.self().post.app_stoped(name)
	end

	nh_map[name] = handle
end

---
-- Handle application events
-- @param event: event type ('start', 'stop', etc.)
-- @param name: application name
-- @param ...: additional event data
---
function accept.app_event(event, name, ...)
	assert(event, 'event is nil')
	assert(name, 'app name is nil')

	if event == 'start' then
		snax.self().post.app_started(name, ...)
	elseif event == 'stop' then
		snax.self().post.app_stoped(name, ...)
	else
		log:trace("Unhandled app event:", event, "for app:", name)
	end
	-- TODO: more events?
end

---
-- Handle application stopped event
-- @param name: application name
---
function accept.app_stoped(name)
	assert(name, 'app name is nil')

	local handle = nh_map[name]
	if not handle then
		return
	end

	local process = handle_to_process(handle)
	log_buffer[process] = nil
	nh_map[name] = nil
end

---
-- Handle application list synchronization
-- @param list: table of application instances
---
function accept.app_list(list)
	for k, v in pairs(list or {}) do
		if v.inst and v.inst.handle then
			nh_map[k] = v.inst.handle
		end
	end
end

---
-- Register a listener for buffer events
-- @param handle: listener service handle
-- @param handle_type: listener service type
---
function accept.listen(handle, handle_type)
	assert(handle and handle_type)
	listen_map[handle] = snax.bind(handle, handle_type)
end

---
-- Unregister a listener
-- @param handle: listener service handle
-- @param handle_type: listener service type
---
function accept.unlisten(handle, handle_type)
	assert(handle)
	listen_map[handle] = nil
end

-- ============================================================================
-- Service Lifecycle
-- ============================================================================

---
-- Connect or disconnect from log server
-- @param enable: true to connect, false to disconnect
---
local function connect_log_server(enable)
	local appmgr = snax.queryservice('appmgr')
	local obj = snax.self()

	if not appmgr then
		log:error("Cannot find appmgr service")
		return false
	end

	if enable then
		local ok, err = pcall(skynet.call, ".logger", "lua", "__LISTEN__", obj.handle, obj.type)
		if not ok then
			log:error("Failed to connect to logger:", err)
			return false
		end
		appmgr.post.listen(obj.handle, obj.type, true)
		log:info("Connected to log server and appmgr")
	else
		local ok, err = pcall(skynet.call, ".logger", "lua", "__UNLISTEN__", obj.handle)
		if not ok then
			log:warning("Failed to disconnect from logger:", err)
		end
		appmgr.post.unlisten(obj.handle)
		log:info("Disconnected from log server and appmgr")
	end

	return true
end

---
-- Initialize buffer service
---
function init()
	log = require 'utils.logger'.new('BUFFER')
	log.notice("System buffer service started!")

	-- Connect to log server and appmgr
	skynet.fork(function()
		connect_log_server(true)
	end)

	-- Initialize app API handler
	skynet.fork(function()
		api = app_api:new('__COMM_DATA_LOGGER')
		api:set_handler(Handler, false)
	end)
end

---
-- Cleanup and shutdown buffer service
---
function exit(...)
	connect_log_server(false)

	log.notice("System buffer service stoped!")
end
