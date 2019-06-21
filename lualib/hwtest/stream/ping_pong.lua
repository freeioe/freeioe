local class = require 'middleclass'
local helper = require 'app.port.helper'
local stream_buffer = require 'app.utils.stream_buffer'
local crc32 = require 'hashings.crc32'
local basexx = require 'basexx'


local test = class("PORT_TEST_PAIR_PING_PONG")

test.static.SK = 'AAA'
test.static.EK = 'FFF'
test.static.hdr_len = 3 + 4
test.static.end_len = 3 + 4

function test:initialize(app, count, max_msg_size, is_ping)
	self._app = app
	self._sys = app._sys
	self._log = app._log
	self._max_count = count or 1000
	self._ping = is_ping

	self._count = 0
	self._failed = 0
	self._passed = 0
	self._droped = 0
	self._send_speed = 0
	self._recv_speed = 0

	self._max_msg_size = max_msg_size or 512

	self._stop = nil
end

function test:out_dump(str)
	local dev = self._app._dev
	if dev then
		dev:dump_comm('OUT', str)
	end
end

function test:in_dump(str)
	local dev = self._app._dev
	if dev then
		dev:dump_comm('IN', str)
	end
end

function test:start(port)
	self._sys:fork(function()
		self:_proc(port)
	end)
	return true
end

function test:_gen_msg()
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

	local data = string.pack('>c'..#test.SK..'s4c'..#test.EK, test.SK, rdata, test.EK)

	--self._log:trace("Data: ", #data)

	return data
end

function test:_proc(port)
	self._stop = nil
	self._send_speed = 0
	self._recv_speed = 0

	local msg_send_total = 0
	local msg_recv_total = 0
	local begin_time = self._sys:time()

	local buf = stream_buffer:new(self._max_msg_size + test.hdr_len + #test.EK)
	local msg = ''
	while not self._stop and not self:finished() do
		--- Clean buffer steam
		buf:clean()

		if self._ping then
			msg = self:_gen_msg()
		end

		local stime = self._sys:time()

		local r, err = port:request(msg, function(port)
			self:out_dump(msg)
			msg_send_total = msg_send_total + #msg
			if self._sys:time() > begin_time + 1 then
				self._send_speed =  math.floor(msg_send_total / (self._sys:time() - begin_time))
			end
			local recv_len = test.hdr_len -- first receive the hdr_len

			while self._sys:time() - stime <= 3000 do
				self._log:trace("Port Reading", recv_len, port)
				local data, err = helper.read_serial(port, recv_len, function(str) self:in_dump(str) end, 3000)
				if not data then
					self._log:trace("Port Reading Err", err)
					return nil, err
				end
				self._log:trace("Port Reading Got", #data)
				buf:append(data)
				msg_recv_total = msg_recv_total + #data
				if self._sys:time() > begin_time + 1 then
					self._recv_speed =  math.floor(msg_recv_total / (self._sys:time() - begin_time))
				end

				local data, len = buf:find(test.SK)
				if data then
					local sk, rlen = string.unpack('>c'..#test.SK..'I4', data)
					-- if rlen < len then
					local data, dlen = buf:find(test.SK, test.EK)
					if data then
						buf:pop(dlen)
						self._log:trace("Got packet", rlen, dlen)
						return true, data, dlen
					else
						recv_len = rlen + test.hdr_len + #test.EK - len
					end
				end
			end
		end, false, 3000)

		self._count = self._count + 1
		self._droped = buf:droped()
		if r then
			self._log:trace("Got data")
			local sk, rdata, ek = string.unpack('>c'..#test.SK..'s4c'..#test.EK, r)
			local crc = string.sub(rdata, -4)
			local rdata = string.sub(rdata, 1, -5)
			-- check crc32
			if crc ~= crc32:new(rdata):digest() then
				self._failed = self._failed + 1
				if not self._ping then
					msg = self:_gen_msg()
				end
			else
				self._passed = self._passed + 1
				if not self._ping then
					msg = r
				end
			end
		else
			self._log:error('Port error', tostring(err))
		end
		--- skip all error /timeout case
		self._sys:sleep(10, self)
	end

	if not self._ping then
		-- last pong message
		local r, err = port:request(msg, function(sock)
			return true
		end)
	end
end

function test:finished()
	return self._max_count <= self._count
end

function test:stop()
	if not self._stop then
		self._stop = true
		self._sys:wakeup(self)
		return true
	end
	return nil, "Stoped"
end

function test:report()
	return {
		count = self._count,
		failed = self._failed,
		passed = self._passed,
		droped = self._droped,
		send_speed = self._send_speed,
		recv_speed = self._recv_speed,
	}
end

return test
