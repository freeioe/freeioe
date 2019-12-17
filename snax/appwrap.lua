local skynet = require 'skynet'
local snax = require 'skynet.snax'
local cache = require "skynet.codecache"
local app_sys = require 'app.sys'
local event = require 'app.event'
local ioe = require 'ioe'

local app = nil
local app_closing = false
local app_name = "UNKNOWN"
local app_log = nil
local mgr_snax = nil
local sys_api = nil

local cancel_ping_timer = nil
local app_ping_timeout = 60000 -- ms -- 60 seconds

local function protect_call(app, func, ...)
	assert(app and func)
	local f = app[func]
	if not f then
		return nil, "Application has no function "..func
	end

	local r, er, err = xpcall(f, debug.traceback, app, ...)
	if not r then
		return nil, er and tostring(er) or nil
	end
	return er, er and tostring(err) or nil
end

local on_close = function(...)
	local clean_up = function(...)
		if sys_api then
			sys_api:cleanup()
		end
		sys_api = nil
		app = nil
		return ...
	end

	if app then
		app_closing = true
		local r, err = protect_call(app, 'close', ...)
		if not r and err then
			return clean_up(nil, err)
		end
	end
	return clean_up(true)
end

local function fire_exception_event(info, data, level)
	if not mgr_snax then
		return
	end
	local data = data or {}
	data.app = app_name
	return mgr_snax.post.fire_event(app_name, ioe.id(), level or event.LEVEL_ERROR, event.EVENT_APP, info, data)
end

local function work_proc()
	local timeout_err = 1000 * 5
	local timeout_err_max = timeout_err * 60
	local timeout = 1000
	--- Sleep one seconds
	skynet.sleep(timeout // 10)

	while app and not app_closing do
		local t, err = protect_call(app, 'run', timeout)
		if t then
			timeout = tonumber(t) or timeout
		else
			if err then
				app_log:warning('App.run returns error:', err)
				fire_exception_event('Application run loop error!', { err=err }, event.LEVEL_WARNING)

				timeout = timeout * 2 -- Double timeout
				if timeout >= timeout_err_max then
					timeout = timeout_err
				end
			end
		end

		--- Sleep before while app do checking
		if timeout > 0 then
			skynet.sleep(timeout // 10)
		end
	end
end

function response.ping()
	return "Pong "..app_name
end

function response.start()
	if app then
		local ping_mgr = nil
		ping_mgr = function()
			mgr_snax.post.app_heartbeat(app_name, skynet.time())
			cancel_ping_timer = app_sys:cancelable_timeout(app_ping_timeout, ping_mgr)
		end
		cancel_ping_timer = app_sys:cancelable_timeout(app_ping_timeout, ping_mgr)

		local r, err = protect_call(app, 'start')
		if not r then
			cancel_ping_timer()
			cancel_ping_timer = nil
			return nil, err
		end

		if app and app.run and not app_closing then
			skynet.timeout(10, work_proc)
		end

		return true
	else
		return nil, "app is nil"
	end
end

function response.stop(...)
	return on_close(...)
end

function response.set_conf(conf)
	if not app then
		return nil, "app is nil"
	end
	sys_api:set_conf(conf)
	if app.reload then
		return protect_call(app, 'reload', conf)
	end
	--- This called from appmgr then we cannot call the mgr_snax.req.restart. so use post
	mgr_snax.post.app_restart(app_name, "Confiruation change restart")
	return true
end

function response.app_req(msg, ...)
	if not app then
		return nil, "app is nil"
	end
	if app.response then
		return protect_call(app, 'response', msg, ...)
	else
		local msg = 'on_req_'..msg
		if app[msg] then
			return protect_call(app, msg, ...)
		end
	end
	return nil, "no handler for request message "..msg
end

function accept.app_post(msg, ...)
	if not app then
		app_log:warning("App is nil when fire event", msg)
		return false
	end

	if app.accept then
		local r, err = protect_call(app, 'accept', msg, ...)
		if not r and err then
			app_log:warning("Failed to call accept function for msg", msg)
			app_log:trace(err)
		end
	else
		local msg = 'on_post_'..msg
		if app[msg] then
			local r, err = protect_call(app, msg, ...)
			if not r and err then
				app_log:warning("Failed to call accept function in application for msg", msg)
				app_log:trace(err)
			end
		else
			app_log:warning("No handler for post message "..msg)
		end
	end
end

function init(name, conf, mgr_handle, mgr_type)
	-- Disable Skynet Code Cache!!
	cache.mode('EXIST')

	app_name = name
	mgr_snax = snax.bind(mgr_handle, mgr_type)
	sys_api = app_sys:new(app_name, mgr_snax, snax.self())
	app_log = sys_api:logger()

	app_log:info("Application starting...")
	package.path = package.path..';./ioe/lualib/compat/?.lua'
	package.path = package.path..";./ioe/apps/"..name.."/?.lua;./ioe/apps/"..name.."/?.luac"..";./ioe/apps/"..name.."/lualib/?.lua;./ioe/apps/"..name.."/lualib/?.luac"
	package.cpath = package.cpath..";./ioe/apps/"..name.."/luaclib/?.so"
	--local r, m = pcall(require, "app")
	local f, err = io.open("./ioe/apps/"..name.."/app.lua", "r")
	if not f then
		app_log:warning("There is no app.lua!, Try to install it")
		skynet.call(".upgrader", "lua", "install_missing_app", name)
		return nil, "Application does not exits!"
	end
	f:close()

	local r, err = skynet.call(".ioe_ext", "lua", "install_depends", name)
	if not r then
		app_log:error("Failed to install depends for ", name, "error:", err)
		local info = "Failed to start app. install depends failed"
		fire_exception_event(info, {ext=name, err=err})
		return nil, info
	end

	local lf, err = loadfile("./ioe/apps/"..name.."/app.lua")
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
		fire_exception_event(err, {err=m})
		return nil, m
	end
	assert(m, "Application class module not found!")

	if m.API_VER and (m.API_VER < app_sys.API_MIN_VER or m.API_VER > app_sys.API_VER) then
		local s = string.format("API Version required is out of range. Required: %d. Current %d-%d",
								m.API_VER, sys_api.API_MIN_VER, sys_api.API_VER)
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

	if not m.new and m.App then
		r, err = xpcall(m.App.new, debug.traceback, app_name, sys_api, conf)
		if not r then
			app_log:error("Create application instance failed.", err)
			fire_exception_event("Create application instance failed.", {err=err})
			return nil, err
		end
		app = err
		return
	end

	r, err = xpcall(m.new, debug.traceback, m, app_name, sys_api, conf)
	if not r then
		app_log:error("Create application instance failed.", err)
		fire_exception_event("Create application instance failed.", {err=err})
		return nil, err
	end
	app = err
end

function exit(...)
	app_log:info("Application closing...")
	if cancel_ping_timer then
		cancel_ping_timer()
		cancel_ping_timer = nil
	end
	local r, err = on_close(...)
	if not r then
		app_log:error(err or 'Unknown application close error')
		--fire_exception_event("App closed failure.", {err=err})
	end
	app_log:info("Application closed!")
end
