local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local api = require 'app.api'
local cjson = require 'cjson'

local sys = class("APP_MGR_SYS")
local args = {...}

function sys:sleep(ms)
	return skynet.sleep(ms / 10)
end

function sys:log(level, ...)
	local f = assert(log[level])
	return f(...)
end

function sys:fork(func, ...)
	local args = {...}
	skynet.fork(function()
		func(table.unpack(args))
	end)
end

function sys:get_data_api(app_name)
	local app_name = app_name or self._app_name
	return api:new(app_name, self._mgr_snax)
end

function sys:read_json(file_name)
	local fp = "./iot/conf/"..self._app_name.."/"..file_name
	local f, err = io.open(fp, "r")
	if not f then
		return nil, err
	end
	local str = f:read("a")
	f:close()
	return cjson.decode(str)
end

function sys:write_json(file_name, data)
	local fp = "./iot/conf/"..self._app_name.."/"..file_name
	local f, err = io.open(fp, "w+")
	if not f then
		return nil, err
	end
	local str = cjson.encode(data)
	f:write(str)
	f:close()
	return true
end

function sys:initialize(mgr_inst, app_name, snax_handle, snax_type)
	self._mgr_snax = snax.bind(snax_handle, snax_type)
	self._app_name = app_name
	self._app_inst = app_inst
	os.execute('mkdir -p ./iot/conf/'..app_name)
end

return sys
