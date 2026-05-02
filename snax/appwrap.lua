---
-- Application Wrapper Service
--
-- This service wraps application instances, providing:
-- - Application lifecycle management (start, stop, restart)
-- - Configuration management and reload
-- - Inter-application communication via appmgr
-- - Heartbeat monitoring and error recovery
-- - Log buffering and forwarding
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local cache = require "skynet.codecache"
local app_sys = require 'app.sys'
local app_util = require 'app.util'
local event = require 'app.event'
local ioe = require 'ioe'

-- ============================================================================
-- Global Variables
-- ============================================================================

G_APP_NAME = 'APP'

-- ============================================================================
-- Constants
-- ============================================================================

-- Timing constants (in centiseconds, as used by skynet)
local PING_TIMEOUT_CS = 60 * 100  -- 60 seconds
local PING_TIMEOUT_ERR_MAX = 10 * PING_TIMEOUT_CS  -- max timeout on error
local DEFAULT_TIMEOUT = 1000     -- default run loop timeout
local LOG_BUFFER_SIZE = 512      -- size of log buffer

-- ============================================================================
-- Module State
-- ============================================================================

local app = nil
local app_closing = false
local app_installing = false
local app_name = "UNKNOWN"
local app_log = nil
local mgr_snax = nil
local sys_api = nil
local log_buffer = nil

local cancel_ping_timer = nil

-- ============================================================================
-- Utility Functions
-- ============================================================================

---
-- Safely call an application method with error protection
-- @param app: application instance
-- @param func: function name to call
-- @param ...: arguments to pass to the function
-- @return: true,result or nil,error_message
---
local function protect_call(app, func, ...)
	if not app then
		return nil, "Application instance is nil"
	end

	if not func or type(func) ~= 'string' then
		return nil, "Invalid function name"
	end

	local f = app[func]
	if not f then
		return nil, "Application has no function "..func
	end

	local r, er, err = xpcall(f, debug.traceback, app, ...)
	if not r then
		return nil, er and tostring(er) or tostring(err)
	end
	return er, err and tostring(err) or 'UNKNOWN ERROR'
end

---
-- Cleanup function called on application close
-- @param ...: arguments to pass to app close method
-- @return: result from cleanup or close operation
---
local on_close = function(...)
	local clean_up = function(...)
		if sys_api then
			sys_api:cleanup()
		end
		sys_api = nil
		app = nil
		log_buffer = nil
		return ...
	end

	if app then
		app_closing = true
		return clean_up(protect_call(app, 'close', ...))
	end
	return clean_up(true)
end

---
-- Fire exception event to appmgr
-- @param info: exception information string
-- @param data: additional data table
-- @param level: event level (default: event.LEVEL_ERROR)
-- @return: result from post call
---
local function fire_exception_event(info, data, level)
	assert(mgr_snax, "mgr_snax not available")
	assert(app_name, "App name missing")
	assert(ioe.id(), "IOE ID missing")
	assert(info, "Exception info missing")

	local data = data or {}
	data.app = app_name

	return mgr_snax.post.fire_event(app_name, ioe.id(), level or event.LEVEL_ERROR, event.EVENT_APP, info, data)
end

---
-- Application work loop processor
-- Handles application run() method, heartbeat, and error recovery
---
local function work_proc()
	local timeout = DEFAULT_TIMEOUT
	--- Initial sleep before starting work loop
	skynet.sleep(timeout // 10)

	if not app.run then
		--- Create fake run function for heartbeat only
		local start = nil
		app.run = function(tms)
			local now = skynet.now()
			--- Send heartbeat at each ping timeout interval
			if not start or (now - start) * 10 >= PING_TIMEOUT_CS then
				mgr_snax.post.app_heartbeat(app_name, now)
				start = now
			end
			return tms
		end
	else
		--- Use timer for heartbeat when app has run() method
		local ping_mgr = function()
			mgr_snax.post.app_heartbeat(app_name, skynet.now())
			cancel_ping_timer = sys_api:cancelable_timeout(PING_TIMEOUT_CS, ping_mgr)
		end
		ping_mgr()
	end

	--- Main application work loop
	while app and not app_closing do
		local t, err = protect_call(app, 'run', timeout)
		if t then
			timeout = tonumber(t) or timeout
		else
			if err then
				app_log:warning('App.run returns error:', err)
				fire_exception_event('Application run loop error!', { err=err }, event.LEVEL_WARNING)

				--- Exponential backoff on error
				timeout = timeout * 2
				if timeout >= PING_TIMEOUT_ERR_MAX then
					timeout = PING_TIMEOUT_ERR_MAX
				end
			end
		end

		--- Sleep before next iteration
		if timeout >= 0 then
			skynet.sleep(timeout // 10)
		else
			timeout = DEFAULT_TIMEOUT
		end
	end
	if not cancel_ping_timer then
		cancel_ping_timer()
		cancel_ping_timer = nil
	end
end

local function publish_log(ts, lvl, ...)
	if not app then
		return false, "App is not exists!"
	end
	local r, er, err = xpcall(app.on_logger, debug.traceback, app, ts, lvl, ...)
	if not r then
		log_buffer = nil
		mgr_snax.post.app_stop(app_name, "app.on_logger code error, so stop app")
		app_log:error(er, err)
		return true
	end
	return er, err
end

local function logger_proc()
	local obj = snax.self()
	skynet.call(".logger", "lua", "__LISTEN__", obj.handle, obj.type)
	while app and not app_closing and log_buffer do
		log_buffer:fire_all()
		skynet.sleep(50)
	end
	skynet.call(".logger", "lua", "__UNLISTEN__", obj.handle)
end

-- ============================================================================
-- Response Handlers
-- ============================================================================

---
-- Ping handler for health check
-- @return: "Pong <app_name>"
---
function response.ping()
	return "Pong "..app_name
end

---
-- Start the application
-- @return: true on success, nil,err on failure
---
function response.start()
	if app then
		local r, err = protect_call(app, 'start')
		if not r then
			skynet.fork(on_close, 'App start failed!')
			return nil, err
		end

		skynet.timeout(100, work_proc)

		if app.on_logger then
			log_buffer = require('buffer.cycle'):new(publish_log, LOG_BUFFER_SIZE)
			skynet.fork(logger_proc)
		end

		return true
	else
		if app_installing then
			return true, "app is installing, and will started after then!"
		end
		return nil, "app instance missing"
	end
end

---
-- Stop the application
-- @param ...: arguments to pass to close method
-- @return: result from on_close
---
function response.stop(...)
	return on_close(...)
end

---
-- Set application configuration
-- @param conf: configuration table
-- @return: true on success, nil,err on failure
---
function response.set_conf(conf)
	if not app then
		return nil, "app is nil"
	end

	if not sys_api then
		return nil, "sys_api not available"
	end

	sys_api:set_conf(conf)

	if app.reload then
		return protect_call(app, 'reload', conf)
	end

	--- This called from appmgr so we cannot call mgr_snax.req.restart, use post instead
	mgr_snax.post.app_restart(app_name, "Configuration change restart")

	return true
end

---
-- Handle application request messages
-- @param msg: message name
-- @param ...: message arguments
-- @return: result from app handler or nil,err
---
function response.app_req(msg, ...)
	if not app then
		return nil, "app is nil"
	end

	assert(msg, "Message name is required")
	if app.response then
		return protect_call(app, 'response', msg, ...)
	else
		local handler_name = 'on_req_'..msg
		if app[handler_name] then
			return protect_call(app, handler_name, ...)
		end
	end

	return nil, "no handler for request message "..msg
end

-- ============================================================================
-- Accept Handlers
-- ============================================================================

---
-- Handle application post messages (asynchronous)
-- @param msg: message name
-- @param ...: message arguments
---
function accept.app_post(msg, ...)
	if not app then
		app_log:warning("App is nil when firing event", msg)
		return false
	end

	assert(msg, "Message name is nil in app_post")

	if app.accept then
		local r, err = protect_call(app, 'accept', msg, ...)
		if not r and err then
			app_log:warning("Failed to call accept function for msg", msg)
			app_log:trace(err)
		end
	else
		local handler_name = 'on_post_'..msg
		if app[handler_name] then
			local r, err = protect_call(app, handler_name, ...)
			if not r and err then
				app_log:warning("Failed to call accept function in application for msg", msg)
				app_log:trace(err)
			end
		else
			app_log:warning("No handler for post message "..msg)
		end
	end
end

---
-- Handle log messages from logger service
-- @param ts: timestamp
-- @param lvl: log level
-- @param msg: log message
-- @param ...: additional log arguments
---
function accept.log(ts, lvl, msg, ...)
	assert(msg, 'message is nil')
	if log_buffer then
		log_buffer:push(ts, lvl, msg, ...)
	end
end

-- ============================================================================
-- Service Lifecycle
-- ============================================================================

---
-- Initialize application wrapper service
-- @param name: application name
-- @param conf: application configuration
-- @param mgr_handle: appmgr service handle
-- @param mgr_type: appmgr service type
-- @return: true on success, nil,err on failure
---
function init(name, conf, mgr_handle, mgr_type)
	assert(name, "Application name is required")
	-- Disable Skynet Code Cache for app development
	cache.mode('EXIST')

	G_APP_NAME = name
	app_name = name

	mgr_snax = assert(snax.bind(mgr_handle, mgr_type))
	sys_api = app_sys:new(app_name, mgr_snax, snax.self())
	app_log = sys_api:logger()

	--- Determine application folder
	local app_folder = ioe.dir()..'/apps/'..name
	if name == app_util.dev_app_name() and conf and conf.__dev_app_path then
		app_folder = conf.__dev_app_path
	end

	app_log:info("Application starting...")

	--- Update package path for application
	--package.path = package.path..';'..ioe.dir()..'/lualib/compat/?.lua' 
	package.path = package.path..";"..app_folder.."/?.lua;"..app_folder.."/?.luac"..";"..app_folder.."/lualib/?.lua;"..app_folder.."/lualib/?.luac"
	package.cpath = package.cpath..";"..app_folder.."/luaclib/?.so"

	--- Check if app.lua exists
	local f, err = io.open(app_folder.."/app.lua", "r")
	if not f then
		app_log:warning("There is no app.lua!, Try to install it")
		app_installing = true
		local r, err = skynet.call(".upgrader", "lua", "install_missing_app", name)
		if not r then
			app_log:info('Install missing app failed', err)
		else
			mgr_snax.post.app_stop(app_name, 'Install missing application')
		end
		return nil, "Application does not exits!"
	end
	f:close()

	--- Install application dependencies
	local r, err = skynet.call(".ioe_ext", "lua", "install_depends", name)
	if not r then
		app_log:error("Failed to install depends for ", name, "error:", err)
		local info = "Failed to start app. install depends failed"
		fire_exception_event(info, {ext=name, err=err})
		return nil, info
	end

	--- Load application module
	local lf, err = loadfile(app_folder.."/app.lua")
	if not lf then
		local info = "Loading application failed."
		app_log:error(info, err)
		fire_exception_event(info, {err=err})
		return nil, err
	end

	local r, m = xpcall(lf, debug.traceback)
	if not r then
		local info = "Loading application failed."
		app_log:error(info, m)
		fire_exception_event(info, {err=m})
		return nil, m
	end

	if not m then
		local err = "Application class module not found!"
		app_log:error(err)
		fire_exception_event(err, {})
		return nil, err
	end

	--- Check API version compatibility
	if m.API_VER and (m.API_VER < app_sys.API_MIN_VER or m.API_VER > app_sys.API_VER) then
		local s = string.format("API Version required is out of range. Required: %d. Current %d-%d",
								m.API_VER, app_sys.API_MIN_VER, app_sys.API_VER)
		app_log:error(s)
		if m.API_VER > app_sys.API_VER then
			app_log:error("Please **UPGRADE** FreeIOE to latest version for running this application.")
		end
		if m.API_VER < app_sys.API_MIN_VER then
			app_log:error("Please **UPDATE** application code to run with current FreeIOE version.")
		end
		fire_exception_event(s, {sys_min_ver=app_sys.API_MIN_VER, sys_ver=app_sys.API_VER, ver=m.API_VER})
		return nil, s
	else
		if not m.API_VER then
			app_log:warning("API_VER is not specified, please use it only for development")
		end
	end

	--- Create application instance
	if not m.new and m.App then
		r, err = xpcall(m.App.new, debug.traceback, app_name, sys_api, conf)
		if not r then
			app_log:error("Create application instance failed.", err)
			fire_exception_event("Create application instance failed.", {err=err})
			return nil, err
		end
		app = err
		return true
	end

	r, err = xpcall(m.new, debug.traceback, m, app_name, sys_api, conf)
	if not r then
		app_log:error("Create application instance failed.", err)
		fire_exception_event("Create application instance failed.", {err=err})
		return nil, err
	end
	app = err
	return true
end

---
-- Cleanup and shutdown application wrapper service
-- @param ...: arguments to pass to on_close
---
function exit(...)
	app_log:info("Application closing...")
	local r, err = on_close(...)
	if not r then
		app_log:error(err or 'Unknown application close error')
		--fire_exception_event("App closed failure.", {err=err})
	end
	app_log:info("Application closed!")
end
