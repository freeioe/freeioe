---
-- UBus Service - OpenWrt UBus Integration
--
-- This service provides an interface between FreeIOE and OpenWrt's UBus system.
-- It exposes system information, configuration, and application management via UBus methods.
--
-- Features:
-- - System information (version, platform, ID, etc.)
-- - Cloud connection status
-- - Configuration management (SYS, CLOUD)
-- - Application management (list, start, stop)
-- - Data retrieval (device or all input data)
-- - System and application upgrade operations
--
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ubus = require 'ubus'
local crypt = require 'skynet.crypt'
local sysinfo = require 'utils.sysinfo'
local app_api = require 'app.api'
local ioe = require 'ioe'

-- ============================================================================
-- Constants
-- ============================================================================

local VALID_CFG_KEYS = {
	SYS = true,
	CLOUD = true,
}

-- ============================================================================
-- Module State
-- ============================================================================

local api = nil
local bus = nil
local log = nil

-- ============================================================================
-- API Handlers
-- ============================================================================

---
-- API Handler for communication and event data
-- Currently logs communication data for debugging purposes
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
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")
		local content = crypt.base64encode(table.concat({...}, '\t'))
		-- Communication data is encoded but not currently processed
		-- Can be extended to log or forward to UBus subscribers
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
		-- Event data can be forwarded to UBus subscribers in future
	end,
}

function response.ping()
	return "PONG"
end

---
-- Create UBus method handlers
-- @param bus: ubus connection object
-- @return: table of method definitions
---
function create_methods(bus)
	return {
		---
		-- Ping method for connectivity testing
		-- @param req: request object
		-- @param msg: message table with optional id and msg fields
		-- @param resp: response function
		-- @return: ubus.STATUS_OK
		---
		ping = {
			function(req, msg, resp)
				resp({
					id = msg.id or 'empty id',
					msg = msg.msg or 'empty message'
				})
				return ubus.STATUS_OK
			end, { id = ubus.INT32, msg = ubus.STRING }
		},
		--[[
		test = {
			function(req, msg)
			print('on test')
			return ubus.STATUS_OK
			end, { id = ubus.INT32, msg = ubus.STRING }
		},
		]]--

		---
		-- Get system information
		-- @return: table with version, platform, ID, etc.
		---
		info = {
			function(req, msg, response)
				local info = {}
				info.version = sysinfo.version()
				info.skynet_version = sysinfo.skynet_version()
				info.firmware_version = sysinfo.firmware_version()
				info.cpu_arch = sysinfo.cpu_arch()
				info.platform = sysinfo.platform()
				info.id = ioe.id()
				info.hw_id = ioe.hw_id()
				info.beta = ioe.beta()
				response(info)
				return ubus.STATUS_OK
			end, {}
		},

		---
		-- Get cloud connection status and configuration
		-- @return: table with host, port, mqtt status, etc.
		---
		cloud = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'
				local cloud = snax.queryservice('cloud')

				if not cloud then
					response({error = "Cloud service not available"})
					return ubus.STATUS_UNKNOWN_ERROR
				end

				local info = {}
				info.host = dc.get("CLOUD", "HOST")
				info.port = dc.get("CLOUD", "PORT")
				info.data_upload = dc.get("CLOUD", "DATA_UPLOAD")
				info.event_upload = dc.get("CLOUD", "EVENT_UPLOAD")
				info.data_cache = dc.get("CLOUD", "DATA_CACHE")
				info.secret = dc.get("CLOUD", "SECRET")

				local online, last, msg_status = cloud.req.get_status()
				info.mqtt = {
					online = online,
					last = last,
					msg = msg_status
				}

				response(info)
				return ubus.STATUS_OK
			end, {}
		},

		---
		-- Get configuration value
		-- @param msg.cfg: configuration section ('SYS' or 'CLOUD')
		-- @return: configuration table or error
		---
		cfg_get = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'

				if not msg or type(msg) ~= 'table' or not msg.cfg then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.cfg) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local cfg_key = string.upper(msg.cfg)
				if not VALID_CFG_KEYS[cfg_key] then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				response(dc.get(cfg_key))
				return ubus.STATUS_OK
			end, {cfg=ubus.STRING}
		},

		---
		-- Set configuration values
		-- @param msg.cfg: configuration section ('SYS' or 'CLOUD')
		-- @param msg.conf: configuration table with key-value pairs
		-- @return: updated configuration or error
		---
		cfg_set = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'

				if not msg or type(msg) ~= 'table' or not msg.cfg or not msg.conf then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.cfg) ~= 'string' or type(msg.conf) ~= 'table' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local cfg_key = string.upper(msg.cfg)
				if not VALID_CFG_KEYS[cfg_key] then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				for k, v in pairs(msg.conf) do
					dc.set(cfg_key, k, v)
				end

				skynet.call(".cfg", "lua", "save")

				response(dc.get(cfg_key))
				return ubus.STATUS_OK
			end, {cfg=ubus.STRING, conf=ubus.TABLE}
		},

		---
		-- Get list of all applications with status
		-- @return: table of applications with running status
		---
		apps = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'
				local apps = dc.get('APPS') or {}
				local appmgr = snax.queryservice('appmgr')

				if not appmgr then
					response({error = "Appmgr service not available"})
					return ubus.STATUS_UNKNOWN_ERROR
				end

				local applist = appmgr.req.list()
				for k, v in pairs(apps) do
					v.running = applist[k] and applist[k].inst or nil
					v.running = v.running and true or false
					v.version = math.floor(tonumber(v.version) or 0)
					v.auto = math.floor(tonumber(v.auto or 1))
				end

				response(apps)
				return ubus.STATUS_OK
			end, {}
		},

		---
		-- Start an application
		-- @param msg.inst: application instance name
		-- @return: {result=true/false, msg=error_message}
		---
		start_app = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.inst then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.inst) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local appmgr = snax.queryservice('appmgr')
				if not appmgr then
					response({result = false, msg = "Appmgr service not available"})
					return ubus.STATUS_UNKNOWN_ERROR
				end

				local r, err = appmgr.req.start(msg.inst)
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {inst=ubus.STRING}
		},

		---
		-- Stop an application
		-- @param msg.inst: application instance name
		-- @return: {result=true/false, msg=error_message}
		---
		stop_app = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.inst then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.inst) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local appmgr = snax.queryservice('appmgr')
				if not appmgr then
					response({result = false, msg = "Appmgr service not available"})
					return ubus.STATUS_UNKNOWN_ERROR
				end

				local r, err = appmgr.req.stop(msg.inst, 'stop from ubus')
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {inst=ubus.STRING}
		},

		---
		-- Get input data (all or specific device)
		-- @param msg.device: optional device name
		-- @return: input data table
		---
		data = {
			function(req, msg, response)
				if msg and msg.device then
					if type(msg.device) ~= 'string' then
						return ubus.STATUS_INVALID_ARGUMENT
					end

					if not api then
						response({error = "API not initialized"})
						return ubus.STATUS_UNKNOWN_ERROR
					end

					local dev, err = api:get_device(msg.device)
					if dev then
						response(dev:data())
					else
						response({error = err or "Device not found"})
					end
				else
					local dc = require 'skynet.datacenter'
					response(dc.get('INPUT') or {})
				end
				return ubus.STATUS_OK
			end, {device=ubus.STRING}
		},

		---
		-- Upgrade system core
		-- @param msg.version: target version (required)
		-- @param msg.skynet: optional skynet version
		-- @return: {result=true/false, msg=error_message}
		---
		upgrade = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.version then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local data = {
					version = msg.version,
					no_ack = 1,
				}

				if msg.skynet then
					data.skynet = {
						version = msg.skynet
					}
				end

				local r, err = skynet.call(".upgrader", "lua", "upgrade_core", req.peer, data)
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {version=ubus.INT32, skynet=ubus.INT32}
		},

		---
		-- Upgrade an application
		-- @param msg.inst: application instance name (required)
		-- @param msg.version: target version (optional)
		-- @return: {result=true/false, msg=error_message}
		---
		upgrade_app = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.inst then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.inst) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local data = {
					inst = msg.inst,
					version = msg.version
				}

				local r, err = skynet.call(".upgrader", "lua", "upgrade_app", req.peer, data)
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, version=ubus.INT32}
		},

		---
		-- Install an application
		-- @param msg.inst: application instance name (required)
		-- @param msg.name: application name (required)
		-- @param msg.version: version (optional)
		-- @param msg.conf: configuration (optional)
		-- @return: {result=true/false, msg=error_message}
		---
		install_app = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.inst or not msg.name then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.inst) ~= 'string' or type(msg.name) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local data = {
					inst = msg.inst,
					version = msg.version,
					name = msg.name,
					conf = msg.conf
				}

				local r, err = skynet.call(".upgrader", "lua", "install_app", req.peer, data)
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, name=ubus.STRING, version=ubus.INT32, conf=ubus.TABLE}
		},

		---
		-- Set application option
		-- @param msg.inst: application instance name (required)
		-- @param msg.option: option name (required)
		-- @param msg.value: option value (required)
		-- @return: {result=true/false, msg=error_message}
		---
		option_app = {
			function(req, msg, response)
				if not msg or type(msg) ~= 'table' or not msg.inst or not msg.option or msg.value == nil then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				if type(msg.inst) ~= 'string' or type(msg.option) ~= 'string' then
					return ubus.STATUS_INVALID_ARGUMENT
				end

				local appmgr = snax.queryservice('appmgr')
				if not appmgr then
					response({result = false, msg = "Appmgr service not available"})
					return ubus.STATUS_UNKNOWN_ERROR
				end

				local r, err = appmgr.req.app_option(msg.inst, msg.option, msg.value)
				response({result = r, msg = err})
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, option=ubus.STRING, value=ubus.STRING}
		}
	}
end

-- ============================================================================
-- Service Lifecycle
-- ============================================================================

---
-- Initialize UBus service
-- @param ...: connection parameters passed to bus:connect()
---
function init(...)
	log = require 'utils.logger'.new('UBUS')

	bus = ubus:new()
	-- bus:connect(...)
	-- bus:connect("172.30.19.103", 11000)
	-- bus:connect("172.30.11.230", 11000)
	-- bus:connect("/tmp/ubus.sock")

	-- Attempt to connect with retry logic
	local max_retries = 3
	local retry_delay = 2000 -- 2 seconds in centiseconds

	for attempt = 1, max_retries do
		local ok, err = pcall(bus.connect, bus, ...)
		if ok then
			local s, status_err = bus:status()
			if s then
				break -- Connection successful
			else
				log:warning('UBus connection check failed:', status_err)
			end
		else
			log:warning('UBus connection attempt', attempt, 'failed:', err)
		end

		if attempt < max_retries then
			log:info('Retrying UBus connection in', retry_delay / 100, 'seconds...')
			skynet.sleep(retry_delay)
		end
	end

	-- Check final connection status
	local s, err = bus:status()
	if not s then
		log:error('Cannot connect to ubusd after', max_retries, 'attempts:', err)
		return
	end

	log:info('UBus connection established')

	-- Create and register UBus methods
	local methods = create_methods(bus)
	local obj_id, obj_type = bus:add('freeioe', methods, function(...)
		log:trace('UBus subscribe callback:', ...)
	end)

	log.notice("System ubus service started!")

	-- Initialize app API
	skynet.fork(function()
		api = app_api:new('UBUS')
		api:set_handler(Handler)
	end)
end

---
-- Cleanup and shutdown UBus service
---
function exit(...)
	log.notice("System ubus service stopped!")
end
