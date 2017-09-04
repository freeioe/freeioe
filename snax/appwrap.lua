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
		if not r then
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
			skynet.fork(work_proc)
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
	sys_api:set_conf(conf)	
	if app and app.reload then
		return protect_call(app, 'reload', conf)
	end
	return nil, "application does not support change configuration when running"
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

	local lf, err = loadfile("./iot/apps/"..name.."/app.lua")
	if not lf then
		log.error("Loading app failed "..err)
		return nil, err
	end
	local r, m = xpcall(lf, debug.traceback)
	if not r then
		log.error("App loading failed "..m)
		return nil, m
	end

	mgr_snax = snax.bind(mgr_handle, mgr_type)
	sys_api = app_sys:new(app_name, mgr_snax, snax.self())

	app = assert(m:new(app_name, conf, sys_api))
end

function exit(...)
	log.info("App "..app_name.." closed.")
	local r, err = on_close(...)
	if not r then
		log.error(err)
	end
end
