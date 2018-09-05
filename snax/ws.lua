local skynet = require "skynet"
local snax = require "skynet.snax"
local socket = require "skynet.socket"
local ioe = require 'ioe'
local websocket = require "websocket"
local httpd = require "http.httpd"
local urllib = require "http.url"
local sockethelper = require "http.sockethelper"
local cjson = require 'cjson.safe'
local log = require 'utils.log'


local client_map = {}
local msg_handler = {}
local handler = {}

local function send_data(client, data)
	local str, err = cjson.encode(data)
	if not str then
		log.error("WebSocket cjson encode error", err)
		return nil, err
	end

	local ws = client.ws
	local r, err = xpcall(ws.send_text, debug.traceback, ws, str)
	if not r then
		log.error("Call send_text failed", err)
		ws:close()
		return nil, err
	end

	client.last = skynet.now()
	return true
end

local function handle_socket(id)
    -- limit request body size to 1024 * 1024 (you can pass nil to unlimit)
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 1024 * 1024)
    if code then
        if header.upgrade == "websocket" then
            local ws = websocket.new(id, header, handler)
            ws:start()
        end
    end
end

local broadcast_id = 0
local function broadcast_msg(code, data)
	broadcast_id = broadcast_id + 1
	for id, client in pairs(client_map) do
		send_data(client, {
			id = broadcast_id,
			code = code,
			data = data,
		})
	end
end

function handler.on_open(ws)
    log.debug(string.format("%d::open", ws.id))
	client_map[ws.id] = {
		ws = ws,
		last = skynet.now(),
		authed = false,
		_in_ping = false,
	}

	-- delay send our information
	local ws_id = ws.id
	skynet.timeout(20, function()
		send_data(client_map[ws_id], {
			id = 1,
			code = 'info',
			data = {
				sn = ioe.id(),
				beta = ioe.beta()
			}
		})
	end)
end

function handler.on_message(ws, message)
    log.debug(string.format("%d receive:%s", ws.id, message))
	--ws:send_text(message .. "from server")

	local client = client_map[ws.id]
	if client then
		client.last = skynet.now()

		local msg, err = cjson.decode(message)

		assert(msg.id and tostring(msg.code))	
		assert(client or msg.code == 'login')

		local f = msg_handler[msg.code]
		if not f then
			return send_data(client, {
				id = id,
				code = code,
				data = {
					result = false,
					message = "Unkown operation code "..msg.code
				}
			})
		else
			return f(msg.id, msg.code, msg.data)
		end
	else
		-- Should not be here
		ws:close()
	end
end

function handler.on_close(ws, code, reason)
    log.debug(string.format("%d close:%s  %s", ws.id, code, reason))
	client_map[ws.id] = nil
end

function handler.on_pong(ws, data)
    log.debug(string.format("%d on_pong %s", ws.id, data))
	local v = client_map[ws.id]
	if v then
		v.last = tonumber(data) or skynet.now()
		v._in_ping = false
	end
end

function msg_handler.login(id, code, data)
end

function msg_handler.app_new(id, code, data)
end

function msg_handler.app_start(id, code, data)
end

function msg_handler.app_stop(id, code, data)
end

function msg_handler.app_list(id, code, data)
end

function msg_handler.app_download(id, code, data)
end

function msg_handler.file_download(id, code, data)
end

function msg_handler.file_upload(id, code, data)
end

function accept.on_log(data)
	broadcast_msg('log', data)
end

function accept.on_comm(data)
	broadcast_msg('comm', data)
end

function accept.on_event(data)
	broadcast_msg('event', data)
end

local function connect_buffer_service(enable)
	local buffer = snax.uniqueservice('buffer')
	local obj = snax.self()
	if enable then
		buffer.post.listen(obj.handle, obj.type)
	else
		logger.post.unlisten(obj.handle)
	end
end

local ws_socket = nil

function init()
	local address = "0.0.0.0:8818"
    log.notice("WebSocket Listening", address)

	skynet.fork(function()
		connect_buffer_service(true)
	end)

    local id = assert(socket.listen(address))
    socket.start(id , function(id, addr)
       socket.start(id)
       pcall(handle_socket, id)
    end)
	ws_socket = id

	skynet.fork(function()
		while true do

			local now = skynet.now()
			for k, v in pairs(client_map) do
				local diff = math.abs(now - v.last)
				local ws = v.ws
				if diff > 60 * 100 then
					log.debug(string.format("%d ping timeout %d-%d", ws.id, v.last, now))
					ws:close(nil, 'Ping timeout')
				end
				if not v._in_ping and diff >= (30 * 100) then
					log.trace(string.format("%d send ping", ws.id))
					ws:send_ping(tostring(now))
					v._in_ping = true
				end
			end

			skynet.sleep(100)
		end
	end)
end

function exit(...)
	connect_buffer_service(false)
	socket.close(ws_socket)
	log.notice("WebSocket service stoped!")
end
