local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local log = require 'utils.log'
local class = require 'middleclass'
local api = require 'app.api'
local lfs = require 'lfs'

local sys = class("APP_MGR_SYS")

function sys:log(level, ...)
	local f = assert(log[level])
	return f(...)
end

function sys:error(...)
	return skynet.error(...)
end

function sys:dump_comm(sn, dir, ...)
	return self._data_api:dump_comm(sn, dir, ...)
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
	if not self._data_api then
		self._data_api = api:new(app_name, self._mgr_snax)
		self._data_api._app_sn = self:app_sn()
	end
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
	app = dc.get("APPS", self._app_name)
	return app.sn
end

-- System ID
function sys:id()
	return dc.get("CLOUD", "ID")
end

function sys:initialize(app_name, mgr_snax, wrap_snax)
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax
	self._app_name = app_name
end

return sys
