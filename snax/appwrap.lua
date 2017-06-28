local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local app_sys = require 'app.sys'

local app = nil
local app_name = "UNKNOWN"

local on_close = function()
	app_name = "UNKNOWN"
	app = nil
end

local function work_proc()
	while app do
		log.trace("work_proc")
		app:run(1000)
		skynet.sleep(0)
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
		skynet.fork(work_proc)
		return true
	else
		return nil, "app is nil"
	end
end

function response.stop(reason)
	if app then
		app:close(reason)
	end
	on_close()
end

function init(name, conf, mgr_handle, mgr_type)
	app_name = name

	log.debug("App "..app_name.." starting")
	local r, m = pcall(require, app_name..".app")
	if not r then
		log.error("App loading failed "..m)
		return nil, m
	end

	local s = snax.self()
	local mgr_inst = snax.bind(mgr_handle, mgr_type)
	local sys = app_sys:new(mgr_inst, app_name, s.handle, s.type)

	app = assert(m:new(app_name, conf, sys))
end

function exit()
	log.debug("App "..app_name.." closed.")
	on_close()
end
