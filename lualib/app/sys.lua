local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local api = require 'app.api'
local cjson = require 'cjson'

local sys = class("APP_MGR_SYS")

function sys:sleep(ms)
	return skynet.sleep(ms / 10)
end

function sys:log(level, ...)
	local f = assert(log[level])
	return f(...)
end

function sys:fork(func)
	skynet.fork(func)
end

function sys:data_api()
	return api:new(self._app_name, self._mgr_snax)
end

function sys:app_dir()
	return "./iot/apps/"..self._app_name.."/"
end

function sys:initialize(mgr_inst, app_name, snax_handle, snax_type)
	self._mgr_snax = snax.bind(snax_handle, snax_type)
	self._app_name = app_name
	self._app_inst = app_inst
	os.execute('mkdir -p ./iot/conf/'..app_name)
end

return sys
