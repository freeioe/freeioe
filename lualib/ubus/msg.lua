local class = require 'middleclass'
local socket = require 'skynet.socket'
local ublob = require 'ubox.blob'
local ublob_buf = require 'ubox.blob_buf'

local umsg = class('ubus.msg')

umsg.static.ALIGN = 4
umsg.static.HDR_LEN = 8
--umsg.static.HDR_FORMAT = '!4>BBHI4'
umsg.static.HDR_FORMAT = '!4>BBHi4'
umsg.static.MAX_MSG_LEN = 1048576
umsg.static.MAX_NOTIFY_PEERS = 16
umsg.static.MSG_VERSION = 0

-- MSG TYPES
umsg.static.HELLO = 0
umsg.static.STATUS = 1
umsg.static.DATA = 2
umsg.static.PING = 3
umsg.static.LOOKUP = 4
umsg.static.INVOKE = 5
umsg.static.ADD_OBJECT = 6
umsg.static.REMOVE_OBJECT = 7
umsg.static.SUBSCRIBE = 8
umsg.static.UNSUBSCRIBE = 9
umsg.static.NOTIFY = 10
umsg.static.MONITOR = 11
umsg.static.MSG_LAST = 12

function umsg.static:read_sock(sock, blob_info)
	local self = self:allocate()
	local min_len = umsg.HDR_LEN + ublob.ATTR_HDR_LEN
	local hdr_data, err = socket.read(sock, min_len)
	--local basexx = require 'basexx'
	--print('read_sock', basexx.to_hex(hdr_data))
	if not hdr_data or string.len(hdr_data) < min_len then
		return nil, "Not enough data for ubus message header, error: "..err
	end
	local blob_len, err = self:parse_hdr(blob_info, hdr_data)
	if not blob_len then
		return nil, err
	end

	--print('Need len', blob_len - ublob.ATTR_HDR_LEN, blob_info)
	if blob_len > ublob.ATTR_HDR_LEN then
		local blob_data, err = socket.read(sock, blob_len - ublob.ATTR_HDR_LEN)
		if not blob_data or string.len(blob_data) < blob_len - ublob.ATTR_HDR_LEN then
			return nil, "Not enough data for ubus message body, error: "..err
		end

		--print('Data ready...')
		local blob_raw = string.sub(hdr_data, umsg.HDR_LEN + 1)..blob_data
		self._buf = assert(ublob_buf:parse(blob_info, blob_raw))
	end

	return self
end

function umsg:parse_hdr(blob_info, raw)
	local ver, typ, seq, peer = string.unpack(umsg.HDR_FORMAT, raw)
	--print('UMSG Header VERSION:', ver, 'TYPE:', typ, 'SEQ:', seq, 'PEER:', peer)
	if typ == umsg.HELLO and ver ~= umsg.MSG_VERSION then
		return nil, "Invalid ubus message version: "..ver
	end

	local bmsg = assert(ublob:parse(blob_info, raw, umsg.HDR_LEN + 1, true))
	if bmsg:raw_len() < ublob.ATTR_HDR_LEN then
		return nil, "Invalid data length found. "..bmsg:raw_len()
	end
	if bmsg:pad_len() > umsg.MAX_MSG_LEN then
		return nil, "Invalid data pad length found. "..bmsg:pad_len()
	end

	self._version = ver
	self._type = typ
	self._seq = seq
	self._peer = peer

	-- Set the data here if nomore stream data needed
	self._buf = bmsg

	return bmsg:raw_len()
end

function umsg:initialize(msg_type, seq, peer, buf)
	self._version = umsg.MSG_VERSION
	self._type = msg_type
	self._seq = seq
	self._peer = peer
	self._buf = buf --- ublob data
end

function umsg:peer()
	return self._peer
end

function umsg:type()
	return self._type
end

function umsg:version()
	return self._version
end

function umsg:seq()
	return self._seq
end

function umsg:blob_buf()
	return self._buf
end

function umsg:find(id)
	return self._buf:find(id)
end

function umsg:data(id)
	local b = self:find(id)
	if not b then
		return nil, "No blob for id "..id
	end
	return b:data()
end

function umsg:dbg_print()
	--print('umsg', self._version, self._type, self._seq, self._peer)
	self._buf:dbg_print()
end

function umsg:__tostring()
	local raw = assert(string.pack(umsg.HDR_FORMAT, self._version, self._type, self._seq, self._peer))
	return raw..tostring(self._buf)
end

return umsg
