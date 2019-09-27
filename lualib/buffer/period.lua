local class = require 'middleclass'
local skynet = require 'skynet'
--local log = require 'utils.log'

local pb = class("_PERIOD_CONSUMER_LIB")

-- Period in ms
-- max_buf_size
-- max_batch_size default will be 1024
function pb:initialize(period, max_buf_size, max_batch_size)
	assert(period and max_buf_size)
	self._period = period
	self._max_size = max_buf_size
	self._max_batch_size = max_batch_size or 1024
	self._buf = {}
	self._cb = nil
end

--- Push one data into buffer
function pb:push(...)
	-- Append to buffer
	self._buf[#self._buf + 1] = {...}
	--print('pb size', self:size())

	--- Check max size
	if not self._max_size then
		return
	end

	--- Drop data if bigger than size
	while #self._buf > self._max_size do
		--- Call data drop callback if has
		if self._drop_cb then
			local data = self._buf[1]
			self._drop_cb(table.unpack(data))
		end

		--log.trace("Drop one data")
		table.remove(self._buf, 1)
	end
end

function pb:_push_front(val_list)
	--log.trace("_push_front", #self._buf, #val_list)
	-- If there is no new data
	if #self._buf == 0 then
		self._buf = val_list
		return
	end

	--- merge data list
	val_list = table.move(self._buf, 1, #self._buf, #val_list + 1, val_list)

	--log.trace("_push_front", #self._buf, #val_list)

	--- Check max size
	if #val_list <= self._max_size then
		self._buf = val_list
		return
	end

	--- Drop data
	local drop_size = #val_list - self._max_size
	--log.trace("Drop data count", drop_size)

	--- Update buffer
	self._buf = table.move(val_list, drop_size + 1, #val_list, 1, {})

	if not self._drop_cb then
		return
	end

	--- Call data drop callback
	for i = 1, drop_size do
		self._drop_cb(table.unpack(val_list[i]))
	end
end

--- Fire all data
function pb:fire_all(cb)
	local cb = cb or self._cb
	assert(cb)
	--log.trace("Buffer size", #self._buf)

	--- swap buffer in case callback will pause
	local buf = self._buf
	self._buf = {}

	if #buf <= 0 then
		return true
	end

	local max_batch_size = self._max_batch_size

	--- No more than max batch call once
	if #buf <= max_batch_size then
		--- less than max batch
		if cb(buf) then
			return true
		else
			--- push back to buffer
			self:_push_front(buf)
			return false
		end
	end

	--log.trace("Sperate buffer", #buf)
	--- create sub list and push to callback
	local offset = 1
	while #buf >= offset do
		--- max_batch_size
		local data = table.move(buf, offset, offset + max_batch_size - 1, 1, {})
		assert(#data <= max_batch_size)
		--log.trace("Sperated data", #data)
		if not cb(data) then
			break
		end
		offset = offset + max_batch_size
	end

	if #buf >= offset then
		if offset ~= 1 then
			buf = table.move(buf, offset, #buf, 1, {})
		end
		---- push back the unfired data
		self:_push_front(buf)
		--log.trace("Now buffer size", #self._buf)
		return false
	end

	return true
end

function pb:reinit(period, size)
	self._period = period or self._period
	self._max_size = size or self._max_size
end

function pb:size()
	return #self._buf
end

function pb:period()
	return self._period
end

function pb:max_size()
	return self._max_size
end

--
-- callback
-- data drop callback
function pb:start(cb, drop_cb)
	assert(cb)
	self._stop = nil
	self._cb = cb
	self._drop_cb = drop_cb
	skynet.fork(function()
		local begin_fire_all = skynet.now()
		local next_fire_all = begin_fire_all
		while not self._stop do
			--print(self._period // 10, begin_fire_all, next_fire_all, skynet.now())
			next_fire_all = next_fire_all + self._period // 10
			self:fire_all(cb)
			--print(self._period // 10, next_fire_all - skynet.now(), skynet.now())
			skynet.sleep(next_fire_all - skynet.now(), self)
		end
	end)
end

function pb:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
	end
end

function pb:__test()
	local o = pb:new(1000, 100, 10)

	local callback_check = 0
	local callback = function(data)
		local cjson = require 'cjson.safe'
		print(cjson.encode(data))
		assert(#data <= 10, 'data size: '..#data)
		assert(callback_check == data[1][1], "callback_check: "..callback_check.." data: "..data[1][1])
		callback_check = callback_check + #data
		--print(data)
		return true
	end

	o:start(callback, function(...) print(...) end)
	local data = 0

	print('work', data)
	while data < 90 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(200)
	print('after sleep')
	print(callback_check)

	callback_check = 100

	while data < 200 do
		o:push(data)
		data = data + 1
	end
	print('enter sleep')
	print(callback_check)
	print('after sleep')
	print(callback_check)

	o:stop()

end

return pb
