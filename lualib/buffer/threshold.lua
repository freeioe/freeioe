local class = require 'middleclass'
local ioe = require 'ioe'

local buffer = class("_ThresHold_Buffer_LIB")

function buffer:initialize(time_gap, count, callback, on_drop_callback)
	assert(time_gap ~= nil and count ~= nil and callback ~= nil)
	self._time_gap = time_gap
	self._count = count
	self._cb = callback
	self._on_drop = on_drop_callback
	self._buf = {}
end

function buffer:clean()
	local now = ioe.time()
	local buf = self._buf
	for i, v in ipairs(self._buf) do
		if now - v.time < self._time_gap then
			--- There no one expired
			if i == 1 then
				return
			end

			--- Only keep those who are not expired
			self._buf = table.move(buf, i, #buf, 1, {})
			return
		end
	end

	--- All expired
	self._buf = {}
end

function buffer:push(...)
	self:clean()
	if #self._buf < self._count then
		table.insert(self._buf, {time=ioe.time(), data={...}})
		return self._cb(...)
	else
		if self._on_drop then
			self._on_drop(...)
		end
		return nil, "Droped as threshold reached!!"
	end
end

function buffer:count()
	self:clean()
	return #self._buf
end

return buffer
