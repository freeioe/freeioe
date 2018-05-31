local skynet = require "skynet"
local service = require "skynet.service"
local class = require 'middleclass'

local app_port = class('IOT_APP_PORT_CLASS')

local function agent_service(...)
	local skynet = require "skynet"

	--skynet.error(...)	-- (...) passed from service.new
	local args = table.pack(...)
	local name = args[1]
	local conf = args[2] or {}

	local command = {}

	function command.open()
		print('open', name, conf)
		return true
	end

	function command.request(request, padding)
		print('request', request, padding)
		return request, padding
	end

	function command.close()
		print('close')
		return true
	end

	skynet.start(function()
		skynet.dispatch("lua", function(session, address, cmd, ...)
			skynet.ret(skynet.pack(command[cmd](...)))
		end)
	end)
end

local function timeout_call(ti, ...)
	local token = {}
	local ret

	skynet.fork(function(...)
		ret = table.pack(pcall(skynet.call, ...))
		skynet.wakeup(token)
	end, ...)

	skynet.sleep(ti, token)
	if ret then
		if ret[1] then
			return table.unpack(ret, 1, ret.n)
		else
			error(ret[2])
		end
	else
		-- timeout
		return false
	end
end

function app_port:initialize(name, conf)
	assert(name)
	local conf = conf or {}

	conf.timeout = conf.timeout or 60 * 100
	self._name = name
	self._conf = conf
	self._agent = service.new("APP.PORT."..name, agent_service, self._name, self._conf)
end

function app_port:__gc()
	self:close()
end

function app_port:open()
	timeout_call(self._conf.timeout, self._agent, "lua", "open")
end

function app_port:close()
	timeout_call(self._conf.timeout, self._agent, "lua", "close")
end

function app_port:request(request, response, padding, timeout)
	timeout_call(timeout or self._conf.timeout, self._agent, "lua", "request", request, padding)
end


return app_port
