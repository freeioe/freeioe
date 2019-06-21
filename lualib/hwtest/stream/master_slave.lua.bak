local class = require 'middleclass'
local helper = require 'app.port.helper'
local stream_buffer = require 'app.utils.stream_buffer'
local crc32 = require 'hashings.crc32'
local basexx = require 'basexx'


local ms = class("PORT_TEST_PAIR_MASTER_SLAVE")

ms.static.SK = 'AAA'
ms.static.EK = 'FFF'
ms.static.hdr_len = 3 + 4
ms.static.end_len = 3 + 4

function ms:initialize(app, count, max_msg_size)
	self._app = app
	self._sys = app._sys
	self._log = app._log
	self._max_count = count or 1000

	self._master_count = 0
	self._master_failed = 0
	self._master_passed = 0
	self._master_droped = 0

	self._slave_count = 0
	self._slave_failed = 0
	self._slave_passed = 0
	self._slave_droped = 0

	self._max_msg_size = max_msg_size or 512


	self._stop = nil
end

function ms:start(master, slave)
	self._sys:fork(function()
		self:_master_proc(master)
	end)
	self._sys:fork(function()
		self:_slave_proc(slave)
	end)
end

function ms:_gen_msg()
	local data_len = math.random(5, self._max_msg_size)
	data_len = data_len - (data_len % 4)
	--self._log:trace("Gen MSG", data_len)

	local buf = {}
	for i = 1, (data_len // 4) - 1 do
		buf[#buf + 1] = string.pack('I4', math.random(1, 0xFFFF))
	end
	local rdata = table.concat(buf)
	local crc = crc32:new(rdata):digest()
	rdata = rdata..crc
	--self._log:trace("CRC:", basexx.to_hex(crc))

	local data = string.pack('>c'..#ms.SK..'s4c'..#ms.EK, ms.SK, rdata, ms.EK)

	--self._log:trace("Data: ", #data)

	return data
end

function ms:_master_proc(port)
	local buf = stream_buffer:new(self._max_msg_size + ms.hdr_len + #ms.EK)

	while not self._stop and not self:finished() do
		--- Clean buffer steam
		buf:clean()

		local msg = self:_gen_msg()
		local stime = self._sys:time()

		local r, err = port:request(msg, function(port)
			local recv_len = ms.hdr_len -- first receive the hdr_len

			while self._sys:time() - stime <= 1000 do
				--self._log:trace("Master Reading", recv_len, port)
				local data, err = helper.read_serial(port, recv_len)
				if not data then
					return nil, err
				end
				buf:append(data)

				local data, len = buf:find(ms.SK)
				if data then
					local sk, rlen = string.unpack('>c'..#ms.SK..'I4', data)
					-- if rlen < len then
					local data, dlen = buf:find(ms.SK, ms.EK)
					if data then
						buf:pop(dlen)
						--self._log:trace("Master Got packet", rlen, dlen)
						return true, data, dlen
					else
						recv_len = rlen + ms.hdr_len + #ms.EK - len
					end
				end
			end
		end, false, 1000)

		self._master_count = self._master_count + 1
		self._master_droped = buf:droped()
		if r then
			--self._log:trace("Master Got data")
			local sk, rdata, ek = string.unpack('>c'..#ms.SK..'s4c'..#ms.EK, r)
			local crc = string.sub(rdata, -4)
			local rdata = string.sub(rdata, 1, -5)
			-- check crc32
			if crc ~= crc32:new(rdata):digest() then
				self._master_failed = self._master_failed + 1
			else
				self._master_passed = self._master_passed + 1
			end
		else
			self._log:error('Master error', tostring(err))
		end
		--- skip all error /timeout case
		self._sys:sleep(10)
	end
end

function ms:_slave_proc(port)
	local buf = stream_buffer:new(self._max_msg_size + ms.hdr_len + #ms.EK)

	local msg = ''
	while not self._stop and self._max_count > self._slave_count do
		--- Clean buffer steam
		buf:clean()

		local stime = self._sys:time()

		local r, err = port:request(msg, function(port)
			local recv_len = ms.hdr_len -- first receive the hdr_len

			while (self._sys:time() - stime) <= 1000 do
				--self._log:trace("Slave Reading", recv_len, port)
				local data, err = helper.read_serial(port, recv_len)
				if not data then
					return nil, err
				end
				buf:append(data)

				local data, len = buf:find(ms.SK)
				if data then
					local sk, rlen = string.unpack('>c'..#ms.SK..'I4', data)
					-- if rlen < len then
					local data, dlen = buf:find(ms.SK, ms.EK)
					if data then
						buf:pop(dlen)
						--self._log:trace("Slave Got packet", rlen, dlen)
						return true, data, dlen
					else
						recv_len = rlen + ms.hdr_len + #ms.EK - len
					end
				end
			end
			return nil, "timeout"
		end, false, 1000)

		self._slave_count = self._slave_count + 1
		self._slave_droped = buf:droped()
		if r then
			--self._log:trace("Slave Got data")
			local sk, rdata, ek = string.unpack('>c'..#ms.SK..'s4c'..#ms.EK, r)
			local crc = string.sub(rdata, -4)
			local rdata = string.sub(rdata, 1, -5)
			--self._log:trace("CRC RECV:", basexx.to_hex(crc))
			-- check crc32
			if crc ~= crc32:new(rdata):digest() then
				self._slave_failed = self._slave_failed + 1
				msg = self:_gen_msg()
			else
				self._slave_passed = self._slave_passed + 1
				msg = r
			end
		else
			self._log:error('Slave error', tostring(err))
		end
		--- skip all error /timeout case
		self._sys:sleep(10)
	end

	local r, err = port:request(msg, function(sock)
		return true
	end)
end

function ms:finished()
	return self._max_count <= self._master_count
end

function ms:report()
	return {
		master = {
			count = self._master_count,
			failed = self._master_failed,
			passed = self._master_passed,
			droped = self._master_droped,
		}, 
		slave = {
			count = self._slave_count,
			failed = self._slave_failed,
			passed = self._slave_passed,
			droped = self._slave_droped,
		}
	}
end

return ms
