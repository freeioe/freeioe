local internal = require "http.internal"
local crypt = require "skynet.crypt"
local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

local M = {}

function M.write_handshake(self, host, url, header)
    local key = crypt.base64encode(crypt.randomkey()..crypt.randomkey())
    local request_header = {
        ["Upgrade"] = "websocket",
        ["Connection"] = "Upgrade",
        ["Sec-WebSocket-Version"] = "13",
        ["Sec-WebSocket-Key"] = key
    }
    if header then
        for k,v in pairs(header) do
            assert(request_header[k] == nil, k)
            request_header[k] = v
        end
    end

    local recvheader = {}
    local code, body = internal.request(self, "GET", host, url, recvheader, request_header)
    if code ~= 101 then
        error(string.format("websocket handshake error: code[%s] info:%s", code, body))
    end

    if not recvheader["upgrade"] or recvheader["upgrade"]:lower() ~= "websocket" then
        error("websocket handshake upgrade must websocket")
    end

    if not recvheader["connection"] or recvheader["connection"]:lower() ~= "upgrade" then
        error("websocket handshake connection must upgrade")
    end

    local sw_key = recvheader["sec-websocket-accept"]
    if not sw_key then
        error("websocket handshake need Sec-WebSocket-Accept")
    end

    sw_key = crypt.base64decode(sw_key)
    if sw_key ~= crypt.sha1(key .. guid) then
        error("websocket handshake invalid Sec-WebSocket-Accept")
    end
end

local op_code = {
    ["frame"]  = 0x00,
    ["text"]   = 0x01,
    ["binary"] = 0x02,
    ["close"]  = 0x08,
    ["ping"]   = 0x09,
    ["pong"]   = 0x0A,
    [0x00]     = "frame",
    [0x01]     = "text",
    [0x02]     = "binary",
    [0x08]     = "close",
    [0x09]     = "ping",
    [0x0A]     = "pong",
}

local function write_frame(self, op, payload_data, masking_key)
    payload_data = payload_data or ""
    local payload_len = #payload_data
    local op_v = assert(op_code[op])
    local v1 = 0x80 | op_v -- fin is 1 with opcode
    local s
    local mask = masking_key and 0x80 or 0x00
    -- mask set to 0
    if payload_len < 126 then
        s = string.pack("I1I1", v1, mask | payload_len)
    elseif payload_len < 0xffff then
        s = string.pack("I1I1>I2", v1, mask | 126, payload_len)
    else
        s = string.pack("I1I1>I8", v1, mask | 127, payload_len)
    end
    self.write(s)

    -- write masking_key
    if masking_key then
        s = string.pack(">I4", masking_key)
        self.write(s)
        payload_data = crypt.xor_str(payload_data, s)
    end

    if payload_len > 0 then
        self.write(payload_data)
    end
end

local function read_frame(self)
    local s = self.read(2)
    local v1, v2 = string.unpack("I1I1", s)
    local fin  = (v1 & 0x80) ~= 0
    -- unused flag
    -- local rsv1 = (v1 & 0x40) ~= 0
    -- local rsv2 = (v1 & 0x20) ~= 0
    -- local rsv3 = (v1 & 0x10) ~= 0
    local op   =  v1 & 0x0f
    local mask = (v2 & 0x80) ~= 0
    local payload_len = (v2 & 0x7f)
    if payload_len == 126 then
        s = self.read(2)
        payload_len = string.unpack(">I2", s)
    elseif payload_len == 127 then
        s = self.read(8)
        payload_len = string.unpack(">I8", s)
    end

    local masking_key = mask and self.read(4) or false
    local payload_data = payload_len>0 and self.read(payload_len) or ""
    payload_data = masking_key and crypt.xor_str(payload_data, masking_key) or payload_data
    return fin, assert(op_code[op]), payload_data
end

local function read_msg(self)
    local recv_buf
    while true do
        local fin, op, payload_data = read_frame(self)
        if op == "close" then
            self.close()
            return false, payload_data
        elseif op == "ping" then
            write_frame(self, "pong", payload_data)
        elseif op ~= "pong" then
            if fin and not recv_buf then
                return payload_data
            else
                recv_buf = recv_buf or {}
                recv_buf[#recv_buf+1] = payload_data
                if fin then
                    local s = table.concat(recv_buf)
                    return s
                end
            end
        end
    end
end

function M.shutdownfunc(conn)
    local op = "close"
    return function()
        write_frame(conn, op)
        conn.close()
    end
end

function M.sendfunc(conn)
    local mask = math.random(0x7FFFFFFF)
    local op = "binary"
    return function(data)
        write_frame(conn, op, data, mask)
    end
end

function M.receivefunc(conn)
    local read_buf = ""
    return function(sz)
        assert(sz)
        while #read_buf < sz do
            local msg = read_msg(conn)
            if not msg then
                return false
            end
            read_buf = read_buf .. msg
        end
        local s = string.sub(read_buf, 1, sz)
        read_buf = string.sub(read_buf, sz+1, #read_buf)
        return s
    end
end

return M
