local class = require 'middleclass'
local blob = require 'ubox.blob'

local blob_buf = class('ubox.blob_buf')

function blob_buf.static:parse(blob_info, raw, pos)
	--local basexx = require 'basexx'
	--print('parse blob_buf', basexx.to_hex(string.sub(raw, pos or 1)))
	local self = self:allocate()
	local head = assert(blob:parse(blob_info, raw, pos))
	self._id = head:id()
	self._blob_info = blob_info

	local data = head:data()
	--print('parse blob_buf data', basexx.to_hex(data))

	local blobs = {}
	local ipos = 1
	while string.len(data) > ipos + blob.ATTR_ALIGN do
		local b = assert(blob:parse(blob_info, data, ipos))
		table.insert(blobs, b)
		ipos = ipos + b:pad_len()
	end

	self._blobs = blobs

	return self
end

function blob_buf:initialize(blob_info, id)
	self._id = id
	self._blob_info = blob_info
	self._blobs = {}
end

function blob_buf:id()
	return self._id
end

function blob_buf:add(blob)
	table.insert(self._blobs, blob)
end

function blob_buf:add_string(id, val)
	self:add(blob:new(self._blob_info, id, string.len(val) + 1, val))
end

function blob_buf:add_raw(id, val)
	self:add(blob:new(self._blob_info, id, string.len(val), val))
end

function blob_buf:add_buf(id, val)
	self:add_raw(id, tostring(val))
end

function blob_buf:add_nested(id)
	local nest = blob_buf:new(self._blob_info, id)
	self:add(nest)
	return nest
end

function blob_buf:add_uint8(id, val)
	self:add(blob:new(self._blob_info, id, 1, val))
end

function blob_buf:add_uint16(id, val)
	self:add(blob:new(self._blob_info, id, 2, val))
end

function blob_buf:add_uint32(id, val)
	self:add(blob:new(self._blob_info, id, 4, val))
end

function blob_buf:add_uint64(id, val)
	self:add(blob:new(self._blob_info, id, 8, val))
end

function blob_buf:add_int8(id, val)
	self:add(blob:new(self._blob_info, id, 1, val))
end

function blob_buf:add_int16(id, val)
	self:add(blob:new(self._blob_info, id, 2, val))
end

function blob_buf:add_int32(id, val)
	self:add(blob:new(self._blob_info, id, 4, val))
end

function blob_buf:add_int64(id, val)
	self:add(blob:new(self._blob_info, id, 8, val))
end

function blob_buf:add_double(id, val)
	self:add(blob:new(self._blob_info, id, 8, val))
end

function blob_buf:get(index)
	return self._blobs[index]
end

function blob_buf:find(id)
	for _, v in ipairs(self._blobs) do
		--print('blob_buf find:', v:id(), id)
		if v:id() == id then
			return v
		end
	end
	return nil, 'Not found'
end

function blob_buf:data(id)
	local b, err = self:find(id)
	if b then
		return b:data()
	end
	return nil, err
end

function blob_buf:__tostring()
	return tostring(self:blob())
end

function blob_buf:dbg_print()
	print('blob_buf start', self._id)
	for _, v in ipairs(self._blobs) do
		v:dbg_print()
	end
	print('blob_buf end', self._id)
end

function blob_buf:blob()
	local list = {}
	for _, v in ipairs(self._blobs) do
		table.insert(list, tostring(v))
	end
	local data = table.concat(list)
	local head = blob:new(self._blob_info, self._id, string.len(data), data)
	return head
end

return blob_buf
