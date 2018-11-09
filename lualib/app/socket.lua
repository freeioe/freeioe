local skynet = require "skynet"
local service = require "skynet.service"
local class = require 'middleclass'
local uuid = require 'uuid'
local log = require 'utils.log'

local app_port = class('FREEIOE_APP_PORT_CLASS')

local function agent_service(...)
	local skynet = require "skynet"
	local socketchannel = require "skynet.socketchannel"
	local log = require 'utils.log'

	--skynet.error(...)	-- (...) passed from service.new
	local args = table.pack(...)
	local name = assert(args[1])
	local conf = args[2] or {}

	local command = {}
	local chn = socketchannel.channel(conf)

	function command.request(request, response, padding)
		local resp, err = assert(load(response))
		if not resp then
			return false, 'Response function code loading failed'
		end

		local r, data, err = skynet.pcall(function()
			return chn:request(request, function(sock)
				local r, data, info = skynet.pcall(resp, sock)
				if not r then
					log.trace(data)
					return false, data
				end
				return data, info
			end, padding)
		end)
		if not r then
			log.trace(data)
			return false, data
		end
		return data, err
	end

	function command.connect(only_once)
		return chn:connect(only_once)
	end

	function command.reopen(new_conf)
		log.trace('reopen socket channel')
		conf = new_conf or conf
		chn:close()
		chn = socketchannel.channel(conf)
	end

	function command.close()
		return chn:close()
	end

	skynet.start(function()
		skynet.dispatch("lua", function(session, address, cmd, ...)
			skynet.ret(skynet.pack(command[cmd](...)))
		end)
	end)
end

local function check(func)
	local info = debug.getinfo(func, "u")
	assert(info.nups == 1)
	assert(debug.getupvalue(func,1) == "_ENV")
end

local timeout_error = setmetatable({}, {__tostring = function() return "[Error: socket timeout]" end })	-- alias for error object

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
			return table.unpack(ret, 2, ret.n)
		else
			error(ret[2])
		end
	else
		-- timeout
		log.trace('timeout error')
		return false, timeout_error
	end
end

function app_port:initialize(conf, share_name)
	assert(conf)
	self._name = share_name or uuid()
	self._conf = conf
	self._agent = service.new(".app_socket_port_"..self._name, agent_service, self._name, self._conf)
end

function app_port:get_name()
	return self._name
end

function app_port:get_conf()
	return self._conf
end

function app_port:connect(only_once, timeout)
	if timeout then
		return self:timeout_call(timeout, "connect", only_once)
	else
		return skynet.call(self._agent, "lua", "connect", only_once)
	end
end

function app_port:timeout_call(timeout, func, ...)
	local r, err = timeout_call(timeout, self._agent, "lua", func, ...)
	if not r and err == timeout_error then
		self:reopen()
	end
	return r, err
end

function app_port:request(request, response, padding, timeout)
	check(response)
	local code = string.dump(response)
	if timeout then
		return self:timeout_call(timeout / 10, "request", request, code, padding)
	else
		return skynet.call(self._agent, "lua", "request", request, code, padding)
	end
end

function app_port:reopen(conf)
	return skynet.call(self._agent, "lua", "reopen", conf)
end

function app_port:close()
	return skynet.call(self._agent, "lua", "close", conf)
end

return app_port
