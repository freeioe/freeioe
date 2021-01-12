-- DOC: https://github.com/cloudwu/skynet/wiki/Socket
local sockethelper = require "http.sockethelper"
local skynet = require "skynet"
local dns = require "skynet.dns"

local regex = {
	host_port = "^([%w%.%-]+):?(%d*)$",
	http_host_port = "^(https?://)([%w%.%-]+):?(%d*).*$",
	websocket = "^(wss?)://([^/]+)(.*)$",
}

function dns_resolve(hostname)
    if hostname:match("^[%.%d]+$") then
        return hostname
    else
        local ok, ret = pcall(dns.resolve, hostname)
        if ok then
            return ret
        else
            return ok
        end
    end
end

local _M = {}

local function init(conn, socket_id)
	conn.socket_id = socket_id
    if conn.secure then
        local tls = require "http.tlshelper"
        local ctx = tls.newctx()

		local cafile = conn.secure_params.cafile
		local capath = conn.secure_params.capath
		if cafile or capath then
			assert(ctx.load_ca, 'CA certs loading not supported by ltls!')
			ctx:load_ca(cafile, capath)
		end

        local cert = conn.secure_params.certificate
        local key = conn.secure_params.key
		local passwd = conn.secure_params.passwd
        if cert and key then
			assert(ctx.set_cert, 'Client certs not supported by ltls!')
            ctx:set_cert(cert, key, passwd)
        end

		local verify = conn.secure_params.verify
		if verify then
			assert(ctx.set_verify, 'Set verify not supported by ltls!')
			ctx:set_verify(verify)
		end

        local tls_ctx = tls.newtls("client", ctx)
        tls.init_requestfunc(socket_id, tls_ctx)()

        conn.close = function ()
            sockethelper.close(socket_id)
            tls.closefunc(tls_ctx)()
        end
        conn.read = tls.readfunc(socket_id, tls_ctx)
        conn.write = tls.writefunc(socket_id, tls_ctx)
        conn.readall = tls.readallfunc(socket_id, tls_ctx)
    else
        conn.close = function ()
            sockethelper.close(socket_id)
        end
        conn.read = sockethelper.readfunc(socket_id)
        conn.write = sockethelper.writefunc(socket_id)
        conn.readall = function ()
            return sockethelper.readall(socket_id)
        end
    end

    if conn.websocket then
        local ws = require "mqtt.skynet.wshelper"
        local mqtt_header = { ["Sec-Websocket-Protocol"] = "mqtt" }
        ws.write_handshake(conn, conn.ws_host, conn.ws_uri, mqtt_header)

        conn.send = ws.sendfunc(conn)
        conn.receive = ws.receivefunc(conn)
        conn.shutdown = ws.shutdownfunc(conn)
    else
        conn.send = conn.write
        conn.receive = conn.read
        conn.shutdown = conn.close
    end
end

local function parse_uri(conn)
    -- try websocket first
    local protocol, host, uri = conn.uri:match(regex.websocket)
    if protocol and not host then
        error(string.format("invalid uri: %s", conn.uri))
    end
    if not protocol then
        host = conn.uri
    end

    local hostname, port = host:match(regex.host_port)
    if not hostname then
        error(string.format("invalid uri: %s", conn.uri))
    end

    -- port
    if port == "" then
        if protocol then
            if protocol == "ws" then
                port = 80
            else
                port = 443
            end
        else
            if conn.secure then
                port = 8883
            else
                port = 1883
            end
        end
    else
        port = tonumber(port)
    end
    conn.port = port

    -- dns
	--[[
    local ip = dns_resolve(hostname)
    if ip then
        conn.host = ip
    else
        error("cannot resolve uri")
    end
	]]--
	conn.host = hostname

    -- websocket
    if protocol then
        conn.websocket = true
        conn.ws_host = hostname
        conn.ws_uri = uri == "" and "/" or uri
        -- force secure
        if protocol == "wss" and not conn.secure then
            conn.secure = true
        end
        if protocol == "ws" then
            conn.secure = false
        end
    end
end

function _M.connect(conn)
    local ok, err = pcall(function()
        -- Do DNS anyway
        parse_uri(conn)

        local timeout = conn._timeout or 500
        local socket_id = sockethelper.connect(conn.host, conn.port, timeout)

        init(conn, socket_id)
    end)
    if ok then
        return ok
    else
        return ok, tostring(err)
    end
end

function _M.shutdown(conn)
    local ok, err = pcall(conn.shutdown)
    if not ok then
        skynet.error(err)
    end
end

function _M.send(conn, data)
    local ok, err = pcall(conn.send, data)
    if not ok then
        skynet.error(err)
    end
    return ok and string.len(data) or false, err
end

function _M.receive(conn, size)
    local ok, data = pcall(conn.receive, size)
    if ok then
        if data then
            return data
        else
            return false, "closed"
        end
    else
        return false, tostring(data)
    end
end

function _M.settimeout(conn, timeout)
	if not timeout then
		conn._timeout = nil
	else
		conn._timeout = timeout * 100
	end
end

return _M
