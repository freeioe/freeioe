local class = require 'middleclass'
local skynet = require 'skynet'

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

function pb:push(...)
	self._buf[#self._buf + 1] = {...}
	--print('pb size', self:size())

	if not self._max_size then
		return
	end

	while #self._buf > self._max_size do
		if self._drop_cb then
			local data = self._buf[1]
			self._drop_cb(table.unpack(data))
		end
		table.remove(self._buf, 1)	
	end
end

function pb:_push_front(val_list)
	if #self._buf == 0 then
		self._buf = val_list
	end

	--- merge list
	for _, v in ipairs(self._buf) do
		val_list[#val_list + 1] = v
	end

	local droped = {}
	while #val_list > self._max_size do
		droped = val_list[0]
		table.remove(val_list, 1)
	end
	self._buf = val_list

	if not self._drop_cb then
		return
	end

	for _, v in ipairs(droped) do
		self._drop_cb(table.unpack(v))
	end
end

function pb:fire_all(cb)
	local cb = cb or self._cb
	assert(cb)

	--- swap buffer
	local buf = self._buf
	self._buf = {}

	if #buf <= 0 then
		return true
	end

	local max_batch_size = self._max_batch_size

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

	--- create sub list and push to callback
	while #buf > 0 do
		--- max_batch_size
		local data = table.move(buf, 1, max_batch_size, 1, {})
		if not cb(data) then
			break
		end
		--- remove the fired data
		buf = table.move(buf, max_batch_size + 1, #buf - max_batch_size, 1, {})
	end

	if #buf > 0 then
		---- push back the unfired data
		self:_push_front(buf)
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
		while not self._stop do
			self:fire_all(cb)
			--print(math.floor(self._period / 10))
			skynet.sleep(math.floor(self._period / 10), self)
		end
		skynet.wakeup(self._stop)
	end)
end

function pb:stop()
	if not self._stop then
		self._stop = {}
		skynet.wait(self._stop)
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
