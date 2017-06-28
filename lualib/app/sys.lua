local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local api = require 'app.api'

local sys = class("APP_MGR_SYS")

function sys:log(level, ...)
	local f = assert(log[level])
	return f(...)
end

function sys:error(...)
	return skynet.error(...)
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
	local cancel = cancelable_timeout(ms / 10, dosomething)
	return cancel
end

function sys:exit()
	skynet.exit()
end

function sys:abort()
	skynet.abort()
end

-- ms
function sys:now()
	return skynet.now() * 10
end


-- seconds
function sys:time()
	return skynet.time()
end

-- seconds
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
	return api:new(self._app_name, self._mgr_snax)
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
	return os.getenv("PWD").."/iot/apps/"..self._app_name.."/"
end

function sys:initialize(mgr_inst, app_name, snax_handle, snax_type)
	self._mgr_snax = snax.bind(snax_handle, snax_type)
	self._app_name = app_name
	self._app_inst = app_inst
end

return sys
