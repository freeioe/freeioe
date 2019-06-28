local skynet = require 'skynet'
local class = require 'middleclass'

local stack = class("UTILS_INDEX_STACK_LIB")

function stack:initialize(max_size, on_drop_cb)
	assert(max_size and on_drop_cb)
	self._max_size = max_size
	self._on_drop_cb = on_drop_cb
	self._buf = {}
end

function stack:push(key, ...)
	self._buf[#self._buf + 1] = {key, ...}
	if #self._buf > self._max_size then
		self._on_drop_cb(table.unpack(self._buf[1]))
	end
end

function stack:remove(key)
	for i, v in ipairs(self._buf) do
		if v[1] == key then
			table.remove(self._buf, i)
			return
		end
	end
end

function stack:fire_all(cb, sleep_count, reset_key)
	local buf = self._buf
	self._buf = {}

	local count = 1
	for _, v in ipairs(buf) do
		local key, err = cb(table.unpack(v, 2))
		if not key then
			break
		end

		if sleep_count then
			if count % sleep_count == 0 then
				skynet.sleep(10)
			end
		end

		count = count + 1
	end

	for i = count, #buf do
		--- append to begining of current qos msg buffer
		local msg = buf[i]
		if reset_key then
			msg[1] = {} --- reset key as there is no for this
		end
		table.insert(self._buf, 1, msg)
	end
end

return stack
