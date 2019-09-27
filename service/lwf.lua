local skynet = require "skynet"
local socket = require "skynet.socket"
local co_m = require "skynet.coroutine"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
--local urllib = require "http.url"
local table = table
local string = string

local option_web = true

local mode, protocol = ...

if mode == "agent" then
protocol = protocol or 'http'

--local cache = require 'skynet.codecache'
local log = require 'utils.log'

local SSLCTX_SERVER = nil
local function gen_interface(protocol, fd)
	if protocol == "http" then
		return {
			init = nil,
			close = nil,
			read = sockethelper.readfunc(fd),
			write = sockethelper.writefunc(fd),
		}
	elseif protocol == "https" then
		local tls = require "http.tlshelper"
		if not SSLCTX_SERVER then
			SSLCTX_SERVER = tls.newctx()
			-- gen cert and key
			-- openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout server-key.pem -out server-cert.pem
			local certfile = skynet.getenv("certfile") or "./server-cert.pem"
			local keyfile = skynet.getenv("keyfile") or "./server-key.pem"
			--print(certfile, keyfile)
			SSLCTX_SERVER:set_cert(certfile, keyfile)
		end
		local tls_ctx = tls.newtls("server", SSLCTX_SERVER)
		return {
			init = tls.init_responsefunc(fd, tls_ctx),
			close = tls.closefunc(tls_ctx),
			read = tls.readfunc(fd, tls_ctx),
			write = tls.writefunc(fd, tls_ctx),
		}
	else
		error(string.format("Invalid protocol: %s", protocol))
	end
end


skynet.start(function()
	--cache.mode('EXIST')

	local lwf_skynet = require 'lwf.skynet.init'
	local lwf_skynet_assets = require 'lwf.skynet.assets'
	local lwf_root = SERVICE_PATH.."/../www"
	--local lwf_root = "/home/cch/mycode/lwf/example"
	local lwf = require('lwf').new(lwf_root, lwf_skynet, lwf_skynet_assets, co_m)

	local processing = nil
	skynet.dispatch("lua", function (_,_,id)
		while processing do
			local ts = skynet.now() - processing
			if ts > 500 then
				log.trace('::LWF:: Web process timeout', processing, skynet.now())
				break
			end
			skynet.sleep(20)
		end
		processing = skynet.now()
		socket.start(id)

		local interface = gen_interface(protocol, id)
		if interface.init then
			interface.init()
		end

		local function response(id, ...)
			local ok, err = httpd.write_response(interface.write, ...)
			if not ok then
				-- if err == sockethelper.socket_error , that means socket closed.
				skynet.error(string.format("fd = %d, %s", id, err))
			end
		end


		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body, httpver = httpd.read_request(interface.read, 4096 * 1024)
		log.trace('::LWF:: Web access', httpver, method, url, code)
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
		if interface.close then
			interface.close()
		end

		skynet.sleep(0)
		processing = nil
	end)
end)

else
local arg = table.pack(...)
assert(#arg <= 3)

skynet.start(function()
	local protocol = #arg >= 3 and arg[1] or 'http'
	local ip = #arg >= 2 and arg[#arg - 1] or "0.0.0.0"
	local port = tonumber(#arg >= 1 and arg[#arg] or 8080)

	if option_web then
		local lfs = require 'lfs'
		if not lfs.attributes(lfs.currentdir().."/ioe/www", "mode") then
			skynet.error("Web not detected, web server closed!!")
			skynet.exit()
		end
	end

	local agent = {}
	for i= 1, 2 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent", protocol)
	end
	local balance = 1
	local id = socket.listen(ip, port)
	skynet.error(string.format("Web listen on %s://%s:%d", protocol, ip, port))
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
