local skynet = require 'skynet'
local class = require 'middleclass'

local stack = class("UTILS_INDEX_STACK_LIB")

function stack:initialize(max_size, on_drop_cb)
	assert(max_size and on_drop_cb)
	self._max_size = max_size
	self._on_drop_cb = on_drop_cb
	self._buf = {}
end

function stack:clean()
	self._buf = {}
end

function stack:size()
	return #self._buf
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

-- when reset_key is ture, all failed send message will keep into buffer with removed key
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

	if count > #buf then
		return
	end
	assert(count <= #buf)

	--- Reset keys
	local new_buf = {}
	for i = count, #buf do
		local msg = buf[i]
		if reset_key then
			msg[1] = {} --- reset key as there is no for this
		end
		new_buf[#new_buf + 1] = msg
	end

	if #self._buf == 0 then
		self._buf = new_buf
	else
		--- Append self._buf to new_buf
		table.move(self._buf, 1, #self._buf, #new_buf + 1, new_buf)
		self._buf = new_buf
	end
end

return stack
