local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local log = require 'utils.log'
local class = require 'middleclass'
local api = require 'app.api'
local logger = require 'app.logger'
local lfs = require 'lfs'

local sys = class("APP_MGR_SYS")
sys.API_VER = 1
sys.API_MIN_VER = 1

function sys:log(level, ...)
	return self._logger(level, ...)
end

function sys:logger()
	return self._logger
end

function sys:dump_comm(sn, dir, ...)
	local sn = sn or self:app_sn()
	return self._data_api:_dump_comm(sn, dir, ...)
end

function sys:fork(func, ...)
	skynet.fork(func, ...)
end

function sys:timeout(ms, func)
	return skynet.timeout(ms / 10, func)
end

function cancelable_timeout(ti, func)
	local function cb()
		if func then
			func()
		end
	end
	local function cancel()
		func = nil
	end
	skynet.timeout(ti, cb)
	return cancel
end


function sys:cancelable_timeout(ms, func)
	local cancel = cancelable_timeout(ms / 10, func)
	return cancel
end

-- Current Application exit
function sys:exit()
	skynet.exit()
end

-- System abort
function sys:abort()
	skynet.abort()
end

-- ms uptime
function sys:now()
	return skynet.now() * 10
end


-- seconds (UTC now)
function sys:time()
	return skynet.time()
end

-- seconds (UTC system start time)
function sys:start_time()
	return skynet.starttime()
end

function sys:yield()
	return skynet.yield()
end

function sys:sleep(ms)
	return skynet.sleep(ms / 10)
end

function sys:data_api()
	return self._data_api
end

function sys:self_co()
	return coroutine.running()
end

function sys:wait()
	return skynet.wait()
end

function sys:wakeup(co)
	return skynet.wakeup(co)
end

function sys:app_dir()
	return lfs.currentdir().."/iot/apps/"..self._app_name.."/"
	--return os.getenv("PWD").."/iot/apps/"..self._app_name.."/"
end

-- Application SN
function sys:app_sn()
	local app_sn = self._app_sn
	if app_sn then
		return app_sn
	end

	app = dc.get("APPS", self._app_name)
	if app then
		app_sn = app.sn
	end
	if not app_sn then
		local cloud = snax.uniqueservice('cloud')
		app_sn = cloud.req.gen_sn(self._app_name)
	end
	self._app_sn = app_sn

	return self._app_sn
end

function sys:get_conf(default_config)
	app = dc.get("APPS", self._app_name)
	local conf = {}
	if app and app.conf then
		conf = app.conf 
	end
	return setmetatable(conf, {__index = default_config})
end

function sys:set_conf(config)
	app = dc.get("APPS", self._app_name)
	if app then
		app.conf = config
		dc.set("APPS", self._app_name, app)
		return  true
	end
end

function sys:version()
	app = dc.get("APPS", self._app_name)
	return app.name, app.version
end

--[[
-- Generate device application
--]]
function sys:gen_sn(dev_name)
	local cloud = snax.uniqueservice('cloud')
	return cloud.req.gen_sn(self._app_name.."."..dev_name)
end

-- System ID
function sys:id()
	return dc.wait("CLOUD", "ID")
end

function sys:initialize(app_name, mgr_snax, wrap_snax)
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax
	self._app_name = app_name
	self._data_api = api:new(app_name, mgr_snax)
	self._app_sn = nil
	self._logger = logger:new(log)
end

function sys:cleanup()
	if self._data_api then
		self._data_api:cleanup()
	end
end

return sys
