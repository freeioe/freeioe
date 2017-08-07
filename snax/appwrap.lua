local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local app_sys = require 'app.sys'

local app = nil
local app_name = "UNKNOWN"
local mgr_snax = nil
local sys_api = nil

local on_close = function()
	if app then
		app:close(reason)
		app = nil
	end
	app_name = "UNKNOWN"
	app = nil
end

local function work_proc()
	local timeout = 1000
	while app do
		skynet.sleep(timeout / 10)
		timeout = app:run(timeout) or timeout
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
	return app:list_devices()
end

--- List device props map by device key which from list_devices
function response.list_props(device)
	assert(app)
	return app:list_props(device)
end

function response.start()
	if app then
		app:start()
		if app.run then
			skynet.fork(work_proc)
		end
		return true
	else
		return nil, "app is nil"
	end
end

function response.stop(reason)
	on_close()
end

function response.set_conf(conf)
	sys_api:set_conf(conf)	
	if app and app.reload then
		return app:reload(conf)
	end
	return nil, "application does not support change configuration when running"
end

function init(name, conf, mgr_handle, mgr_type)
	app_name = name

	log.debug("App "..app_name.." starting")
	package.path = package.path..";./iot/apps/"..name.."/?.lua;./iot/apps/"..name.."/?.luac"
	package.cpath = package.cpath..";./iot/apps/"..name.."/luaclib/?.so"
	--local r, m = pcall(require, "app")
	local f, err = loadfile("./iot/apps/"..name.."/app.lua")
	local r, m = pcall(f)
	if not r then
		log.error("App loading failed "..m)
		return nil, m
	end

	mgr_snax = snax.bind(mgr_handle, mgr_type)
	sys_api = app_sys:new(app_name, mgr_snax, snax.self())

	app = assert(m:new(app_name, conf, sys_api))
end

function exit()
	log.debug("App "..app_name.." closed.")
	on_close()
end
