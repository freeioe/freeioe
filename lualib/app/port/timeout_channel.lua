local skynet = require "skynet"
local class = require 'middleclass'
local uuid = require 'uuid'
local log = require 'utils.log'

local app_port = class('FREEIOE_APP_SERIAL_PORT_CLASS')

local function port_request(chn, request, response, padding)
	local r, data, err = skynet.pcall(chn.request, chn, request, function(sock)
		local r, data, info = skynet.pcall(response, sock)
		if not r then
			--log.trace(data)
			return false, data
		end
		return data, info
	end, padding)

	if not r then
		--log.trace(data)
		return false, data
	end
	return data, err
end

local timeout_error = setmetatable({}, {__tostring = function() return "[Error: channel timeout]" end })	-- alias for error object

local function timeout_call(ti, f, ...)
	local token = {}
	local ret

	skynet.fork(function(...)
		ret = table.pack(pcall(f, ...))
		skynet.wakeup(token)
	end, ...)

	skynet.sleep(ti, token)
	if ret then
		if ret[1] then
			return table.unpack(ret, 2)
		else
			error(ret[2])
		end
	else
		-- timeout
		--log.trace('timeout error')
		return false, timeout_error
	end
end

function app_port:initialize(port_type, conf, share_name)
	local r, m = pcall(require, port_type)
	assert(r, m)
	assert(conf, "Serial port configuration missing")

	self._name = share_name or uuid()
	self._conf = conf
	self._port_m = m
	self._chn = m.channel(conf)
end

function app_port:get_name()
	return self._name
end

function app_port:get_conf()
	return self._conf
end

function app_port:connect(only_once, timeout)
	if timeout then
		return self:timeout_call(timeout, self._chn.connect, self._chn, only_once)
	else
		return self._chn:connect(only_once)
	end
end

function app_port:timeout_call(timeout, func, ...)
	local r, err = timeout_call(timeout, func, ...)
	--[[
	if not r and err == timeout_error then
		log.error('Port timeout then reopen it')
		self:reopen()
	end
	]]--
	return r, err
end

function app_port:request(request, response, padding, timeout)
	if timeout then
		return self:timeout_call(timeout / 10, port_request, self._chn, request, response, padding)
	else
		return port_request(self._chn, request, response, padding)
	end
end

function app_port:reopen(conf)
	if self._chn then
		self._chn:close()
	end
	self._chn = self._port_m.channel(conf or self._conf)
end

function app_port:close()
	if self._chn then
		self._chn:close()
		self._chn = nil
	end
end

return app_port
