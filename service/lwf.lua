local skynet = require "skynet"
local socket = require "skynet.socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string

local mode = ...

if mode == "agent" then

local cache = require 'skynet.codecache'
local log = require 'utils.log'

local function response(id, ...)
	local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		skynet.error(string.format("fd = %d, %s", id, err))
	end
end

skynet.start(function()
	cache.mode('EXIST')

	local lwf_skynet = require 'lwf.skynet.init'
	local lwf_root = SERVICE_PATH.."/../www"
	local lwf = require('lwf').new(lwf_root, lwf_skynet)

	skynet.dispatch("lua", function (_,_,id)
		socket.start(id)

		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body, httpver = httpd.read_request(sockethelper.readfunc(id), 8192)
		log.trace('Web access', httpver, method, url, code)
		if code then
			if code ~= 200 then
				response(id, code)
			else
				local r, err = xpcall(lwf, debug.traceback, method, url, header, body, httpver, id, response)
				if not r then
					response(id, 500, err)
				end
			end
		else
			if url == sockethelper.socket_error then
				--skynet.error("socket closed")
			else
				skynet.error(url)
			end
		end
		socket.close(id)
	end)
end)

else
local arg = table.pack(...)
assert(arg.n <= 2)

skynet.start(function()
	local ip = (arg.n == 2 and arg[1] or "0.0.0.0")
	local port = tonumber(arg[arg.n] or 8090)

	local agent = {}
	for i= 1, 4 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent")
	end
	local balance = 1
	local id = socket.listen(ip, port)
	skynet.error("Web listen on:", port)
	socket.start(id , function(id, addr)
		--skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
		skynet.send(agent[balance], "lua", id)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
end)

end
