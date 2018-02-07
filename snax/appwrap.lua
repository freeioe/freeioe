local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local app_sys = require 'app.sys'
local cache = require "skynet.codecache"

local app = nil
local app_name = "UNKNOWN"
local mgr_snax = nil
local sys_api = nil

local function protect_call(app, func, ...)
	assert(app and func)
	local f = app[func]
	if not f then
		return nil, "App has no function "..func
	end

	local r, er, err = xpcall(f, debug.traceback, app, ...)
	if not r then
		return nil, er
	end
	return er, err
end

local on_close = function(...)
	if app then
		local r, err = protect_call(app, 'close', ...)
		if not r and err then
			return nil, err
		end
	end
	if sys_api then
		sys_api:cleanup()
	end
	sys_api = nil
	app = nil
	app_name = "UNKNOWN"
	app = nil
	return true
end

local function work_proc()
	local timeout = 1000
	while app do
		skynet.sleep(timeout / 10)

		local t, err = protect_call(app, 'run', timeout)
		if t then
			timeout = t
		else
			if err then
				log.warning(err)
				timeout = 1000 * 60
			end
		end
	end
end

function response.ping()
	return "Pong "..app_name
end

--[[
-- List device map {<device_key> = {...}}
--]]
function response.list_devices()
	assert(app)
	return protect_call(app, 'list_device')
end

--- List device props map by device key which from list_devices
function response.list_props(device)
	assert(app)
	return protect_call(app, 'list_props')
end

function response.start()
	if app then
		local r, err = protect_call(app, 'start')
		if not r then
			return nil, err
		end

		if app.run then
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
	return mgr_snax.req.restart(app_name, "Confiruation change restart")
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
		return nil, "app is nil"
	end
	if app.accept then
		return protect_call(app, 'accept', msg, ...)
	else
		local msg = 'on_post_'..msg
		if app[msg] then
			return protect_call(app, msg, ...)
		end
	end
	return nil, "no handler for post message "..msg
end

function init(name, conf, mgr_handle, mgr_type)
	-- Disable Skynet Code Cache!!
	cache.mode('EXIST')

	app_name = name

	log.info("App "..app_name.." starting")
	package.path = package.path..";./iot/apps/"..name.."/?.lua;./iot/apps/"..name.."/?.luac"
	package.cpath = package.cpath..";./iot/apps/"..name.."/luaclib/?.so"
	--local r, m = pcall(require, "app")
	local f, err = io.open("./iot/apps/"..name.."/app.lua", "r")
	if not f then
		log.warning("Application does not exits!, Try to install it")	
		skynet.call("UPGRADER", "lua", "install_missing_app", name)
		return nil, "App does not exits!"
	end
	f:close()

	local r, err = skynet.call("IOT_EXT", "lua", "install_depends", name)
	if not r then
		log.error("Failed to install depends for ", name, "error:", err)
		return nil, "Failed to start app. install depends failed"
	end

	local lf, err = loadfile("./iot/apps/"..name.."/app.lua")
	if not lf then
		log.error("Loading app failed "..err)
		return nil, err
	end
	local r, m = xpcall(lf, debug.traceback)
	if not r then
		log.error("Loading app failed "..m)
		return nil, m
	end

	if m.API_VER and m.API_VER < app_sys.API_MIN_VER then
		local s = string.format("API Version required is too old. Required: %d. Current %d-%d",
								m.API_VER, sys_api.API_MIN_VER, sys_api.API_VER)
		log.error(s)
		return nil, s
	else
		if not m.API_VER then
			log.warning("API Version is not specified, please use it only for development")
		end
	end

	mgr_snax = snax.bind(mgr_handle, mgr_type)
	sys_api = app_sys:new(app_name, mgr_snax, snax.self())

	r, err = xpcall(m.new, debug.traceback, m, app_name, sys_api, conf)
	if not r then
		log.error("Create App instance failed. ", err)
		return nil, err
	end
	app = err
end

function exit(...)
	log.info("App "..app_name.." closed.")
	local r, err = on_close(...)
	if not r then
		log.error(err)
	end
end
