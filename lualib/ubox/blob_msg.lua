local blob = require 'ubox.blob'

local class = require 'middleclass'

local blob_msg = class('ubox.blob_msg')

blob_msg.static.ALIGN = 4
blob_msg.static.HDR_FORMAT = '!2>s2'
blob_msg.static.HDR_LEN = 2

blob_msg.static.UNSPEC = 0
blob_msg.static.ARRAY = 1
blob_msg.static.TABLE = 2
blob_msg.static.STRING = 3
blob_msg.static.INT64 = 4
blob_msg.static.INT32 = 5
blob_msg.static.INT16 = 6
blob_msg.static.INT8 = 7
blob_msg.static.DOUBLE = 8
blob_msg.static.BOOL = 8
blob_msg.static.LAST = 8

local msg_blob_info = {
	[blob_msg.INT8] = { len = 1, fmt = '>i1' },
	[blob_msg.INT16] = { len = 2, fmt = '>i2' },
	[blob_msg.INT32] = { len = 4, fmt = '>i4' },
	[blob_msg.INT64] = { len = 8, fmt = '>i8' },
	[blob_msg.DOUBLE] = { len = 8, fmt = '>d' },
	[blob_msg.STRING] = { len = 0 },
	[blob_msg.UNSPEC] = { len = 0 },
	[blob_msg.ARRAY] = { len = 0 },
	[blob_msg.TABLE] = { len = 0 },
}
blob_msg.static.blob_info = msg_blob_info

function blob_msg.static:parse(blob_info, raw, pos)
	local self = self:allocate()
	local pos = pos or 1
	--local basexx = require 'basexx'
	--print('parse blob_msg', basexx.to_hex(string.sub(raw, pos)))
	local head = assert(blob:parse(blob_info, raw, pos))

	local data = head:data()
	local name, index = string.unpack(blob_msg.HDR_FORMAT, data)
	self._name = name
	self._len = head:len() - self:hdr_len()

	pos = self:hdr_len() + 1
	local bi = blob_msg.blob_info[head:id()]
	local data_len = 0
	if bi and bi.fmt then
		self._data = string.unpack(bi.fmt, data, pos)
		data_len = bi.len or 0
	else
		if head:id() == blob_msg.STRING then
			data_len = head:len() - self:hdr_len()
			self._data = string.sub(data, pos, pos + self._len - 2)
		end
	end
	pos = pos + self:padding_len(data_len)

	--print('blob_msg name:', self._name, 'msg_type:', head:id(), 'len:', head:len())

	local blobs = {}
	if head:id() == blob_msg.TABLE or head:id() == blob_msg.ARRAY then
		while string.len(data) > pos + blob.ATTR_HDR_LEN + blob_msg.HDR_LEN do
			local b = assert(blob_msg:parse(blob_info, data, pos))
			table.insert(blobs, b)
			--print('parse blob_msg pos', pos, b:pad_len())
			pos = pos + b:pad_len()
		end
		--print('blob_msg', self._name, 'contains blob count: ', #blobs)
	end
	self._blobs = blobs

	return self
end

function blob_msg.static:from_blob(blob_info, blob_obj)
	assert(blob_obj)
	return blob_msg:parse(blob_info, tostring(blob_obj))
end

local msglua_types =  {
	boolean = blob_msg.INT8,
	integer = blob_msg.INT32,
	double = blob_msg.DOUBLE,
	string = blob_msg.STRING
}
function blob_msg.static:from_lua(blob_info, name, val)
	if type(val) == 'boolean' then
		val = val and 1 or 0
	end
	assert(val)
	local self = self:allocate()
	self._blob_info = blob_info
	self._id = blob_msg.UNSPEC
	self._name = name
	self._len = 0
	self._blobs = {}

	local val_type = type(val)
	if val_type == 'boolean' then
		self._id = blob_msg.INT8
		self._len = 1
		self._data = val == true and 1 or 0
	elseif val_type == 'number' then
		if math.tointeger(val) then
			if val > 0x7FFFFFFF then
				self._id = blob_msg.INT64
				self._len = 8
			else
				self._id = blob_msg.INT32
				self._len = 4
			end
		else
			self._id = blob_msg.DOUBLE
			self._len = 8
		end
		self._data = val
	elseif val_type == 'string' then
		self._id = blob_msg.STRING
		self._data = val
		self._len = string.len(val) + 1
	elseif val_type == 'table' then
		if #val ~= 0 then
			self._id = blob_msg.ARRAY
			for _, v in pairs(val) do
				local b = blob_msg:from_lua(self._blob_info, '', v)
				table.insert(self._blobs, b)
			end
		else
			self._id = blob_msg.TABLE
			for k, v in pairs(val) do
				local b = blob_msg:from_lua(self._blob_info, k, v)
				table.insert(self._blobs, b)
			end
		end
	else
		assert(false, "Unknown lua type "..val_type.." name: "..self._name)
	end

	return self
end

function blob_msg:initialize(blob_info, id, name, len, data)
	self._blob_info = blob_info
	self._id = id
	self._name = name
	self._len = len
	self._data = data
	self._blobs = {}
end

function blob:dbg_print()
	print('blob_msg', self._id, self._name, self._len)
	if not self._blobs or #self._blobs == 0 then
		return
	end
	for _, v in ipairs(self._blobs) do
		v:dbg_print()
	end
	print('blob_msg end', self._id, self._name, self._len)
end

function blob_msg:hdr_len()
	local len = blob_msg.HDR_LEN + string.len(self._name) + 1
	return (len + blob_msg.ALIGN - 1) & ~(blob_msg.ALIGN - 1)
end

function blob_msg:raw_len()
	return self:hdr_len() + blob.ATTR_HDR_LEN + (self._len or 0)
end

function blob_msg:padding_len(len)
	return (len + blob.ATTR_ALIGN - 1) & ~(blob.ATTR_ALIGN - 1)
end

function blob_msg:pad_len()
	return (self:raw_len() + blob.ATTR_ALIGN - 1) & ~(blob.ATTR_ALIGN - 1)
end

function blob_msg:__tostring()
	return tostring(self:blob())
end

function blob_msg:blob()
	local list = {}
	for _, v in ipairs(self._blobs) do
		table.insert(list, tostring(v))
	end

	--print('message header len', string.len(msg_hdr))
	local msg_hdr = string.pack(blob_msg.HDR_FORMAT, self._name)
	if self:hdr_len() > string.len(msg_hdr) then
		msg_hdr = msg_hdr..string.rep('\0', self:hdr_len() - string.len(msg_hdr))
	end
	local data = msg_hdr

	if self._len and self._len > 0 then
		local bi = blob_msg.blob_info[self._id]
		if bi and bi.fmt then
			data = data .. string.pack(bi.fmt, self._data)
		else
			data = data .. self._data
		end
		local pad_len = self:pad_len() - blob.ATTR_HDR_LEN
		if pad_len > string.len(data) then
			data = data..string.rep('\0', pad_len - string.len(data))
		end
	end
	data = data .. table.concat(list)

	local head = blob:new(self._blob_info, self._id, string.len(data), data, true)

	return head
end

function blob_msg:name()
	return self._name
end

function blob_msg:msg2lua()
	--local val = self._data
	--print(self._name, #self._blobs)
	if #self._blobs == 0 then
		return self._name, self._data or {}
	end

	local childs = {}
	for _, v in ipairs(self._blobs) do
		local name, data = v:msg2lua()
		if string.len(name) > 0 then
			childs[name] = data
		else
			table.insert(childs, data)
		end
	end
	return self._name, childs
end

return blob_msg
