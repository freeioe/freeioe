local skynet = require 'skynet'
local class = require 'middleclass'

local stack = class("UTILS_INDEX_STACK_LIB")

--- on_drop_cb returns true will remove the buffered data, or keep it
function stack:initialize(max_size, on_drop_cb)
	assert(max_size and on_drop_cb)
	self._max_size = max_size
	self._on_drop_cb = on_drop_cb
	self._buf = {}
end

function stack:clean()
	self._buf = {}
end

function stack:full()
	return #self._buf >= self._max_size
end

function stack:size()
	return #self._buf
end

function stack:max()
	return self._max_size
end

function stack:set_max(size, skip_drop)
	if skip_drop or self._max_size < size then
		self._max_size = size
	end
	while #self._buf > size do
		if self._on_drop_cb(table.unpack(self._buf[1])) then
			table.remove(self._buf, 1)
		end
	end
	self._max_size = size
end

function stack:push(key, ...)
	self._buf[#self._buf + 1] = {key, ...}
	if #self._buf > self._max_size then
		if self._on_drop_cb(table.unpack(self._buf[1])) then
			table.remove(self._buf, 1)
		end
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
	if #buf == 0 then
		return
	end

	--- Create new buffer list
	self._buf = {}

	--- Fire all message
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

	--- If all done
	if count > #buf then
		return
	end

	--- Push back to buffer
	--- And Reset keys if reset_key is true
	local new_buf = {}
	for i = count, #buf do
		local msg = buf[i]
		if reset_key then
			msg[1] = {} --- reset key as there is no for this
		end
		new_buf[#new_buf + 1] = msg
	end

	if #self._buf == 0 then
		--- Swap buffer when _buf is empty
		self._buf = new_buf
	else
		--- Append self._buf to new_buf
		table.move(self._buf, 1, #self._buf, #new_buf + 1, new_buf)
		self._buf = new_buf
	end
end

return stack
