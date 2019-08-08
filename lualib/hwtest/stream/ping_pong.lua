local skynet = require 'skynet'
local class = require 'middleclass'
local helper = require 'app.port.helper'
local stream_buffer = require 'app.utils.stream_buffer'
local log = require 'utils.log'
local crc16 = require 'hwtest.crc16'
local basexx = require 'basexx'


local test = class("PORT_TEST_PAIR_PING_PONG")

test.static.SK = 'AAA'
test.static.EK = 'FFF'
test.static.hdr_len = 3 + 4
test.static.end_len = 3 + 4

function test:initialize(count, max_msg_size, is_ping)
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

function test:start(port)
	skynet.fork(function()
		self:_proc(port)
	end)
	return true
end

function test:_gen_msg()
	local data_len = math.random(5, self._max_msg_size)
	data_len = data_len - (data_len % 4)

	local buf = {}
	for i = 1, (data_len // 4) - 1 do
		buf[#buf + 1] = string.pack('I4', math.random(1, 0xFFFF))
	end
	local rdata = table.concat(buf)
	local crc = crc16(rdata)
	rdata = rdata..crc

	local data = string.pack('>c'..#test.SK..'s4c'..#test.EK, test.SK, rdata, test.EK)

	return data
end

function test:_proc(port)
	self._stop = nil
	self._send_speed = 0
	self._recv_speed = 0

	if self._ping then
		skynet.sleep(20, self)
	end

	local msg_send_total = 0
	local msg_recv_total = 0
	local begin_time = skynet.time()

	local buf = stream_buffer:new(self._max_msg_size + test.hdr_len + #test.EK)
	local msg = ''
	while not self._stop and not self:finished() do
		--- Clean buffer steam
		buf:clean()

		if self._ping then
			msg = self:_gen_msg()
		end

		local stime = skynet.time()

		local r, err = port:request(msg, function(port)
			--self:out_dump(msg)
			msg_send_total = msg_send_total + #msg
			if skynet.time() > begin_time + 1 then
				self._send_speed =  math.floor(msg_send_total / (skynet.time() - begin_time))
			end
			local recv_len = test.hdr_len -- first receive the hdr_len

			while skynet.time() - stime <= 3000 do
				log.trace("Port Reading", recv_len, port)
				local data, err = helper.read_serial(port, recv_len, function(str) return; --[[self:in_dump(str)]] end, 3000)
				if not data then
					log.trace("Port Reading Err", err)
					return nil, err
				end
				log.trace("Port Reading Got", #data)
				buf:append(data)
				msg_recv_total = msg_recv_total + #data
				if skynet.time() > begin_time + 1 then
					self._recv_speed =  math.floor(msg_recv_total / (skynet.time() - begin_time))
				end

				local data, len = buf:find(test.SK)
				if data then
					local sk, rlen = string.unpack('>c'..#test.SK..'I4', data)
					-- if rlen < len then
					local data, dlen = buf:find(test.SK, test.EK)
					if data then
						buf:pop(dlen)
						log.trace("Got packet", rlen, dlen)
						return true, data, dlen
					else
						recv_len = rlen + test.hdr_len + #test.EK - len
					end
				else
					log.warning("Failed to find SK", data, len)
				end
			end
		end, false, 3000)

		self._count = self._count + 1
		self._droped = buf:droped()
		log.info('Finished count', self._count, r ~= false)
		if r then
			log.trace("Got data")
			local sk, rdata, ek = string.unpack('>c'..#test.SK..'s4c'..#test.EK, r)
			local crc = string.sub(rdata, -2)
			local rdata = string.sub(rdata, 1, -3)
			-- check crc
			if crc ~= crc16(rdata) then
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
			self._failed = self._failed + 1
			msg = self:_gen_msg()
			log.error('Port error', tostring(err))
		end
		--- skip all error /timeout case
		skynet.sleep(10, self)
	end

	if not self._ping then
		-- last pong message
		local r, err = port:request(msg, function(sock)
			return true
		end, false, 3000)
		if not r then
			self._failed = self._failed + 1
			log.error('Port error', tostring(err))
		end
	end
end

function test:finished()
	return self._max_count <= self._count
end

function test:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
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
