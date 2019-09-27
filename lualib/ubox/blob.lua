local class = require 'middleclass'
--local basexx = require 'basexx'

local blob = class('ubox.blob')

blob.static.COOKIE = 0x01234567

blob.static.ATTR_UNSPEC = 0
blob.static.ATTR_NESTED = 1
blob.static.ATTR_BINARY = 2
blob.static.ATTR_STRING = 3
blob.static.ATTR_INT8 = 4
blob.static.ATTR_INT16 = 5
blob.static.ATTR_INT32 = 6
blob.static.ATTR_INT64 = 7
blob.static.ATTR_DOUBLE = 8
blob.static.ATTR_LAST = 9

local attr_types = {
	[blob.ATTR_UNSPEC] = 'raw',
	[blob.ATTR_NESTED] = 'nested',
	[blob.ATTR_BINARY] = 'string',
	[blob.ATTR_STRING] = 'string',
	[blob.ATTR_INT8] = 'int8',
	[blob.ATTR_INT16] = 'int16',
	[blob.ATTR_INT32] = 'int32',
	[blob.ATTR_INT64] = 'int64',
	[blob.ATTR_DOUBLE] = 'double',
}
local function get_type(attr_type)
	if type(attr_type) == 'string' then
		return attr_type
	end
	return attr_types[attr_type]
end

local blob_type_unpack = {
	bool = function(blob_info, data, pos, len) return string.unpack('>I1', data, pos) ~= 0 end,
	int8 = function(blob_info, data, pos, len) return string.unpack('>i1', data, pos) end,
	int16 = function(blob_info, data, pos, len) return string.unpack('>i2', data, pos) end,
	int32 = function(blob_info, data, pos, len) return string.unpack('>i4', data, pos) end,
	int64 = function(blob_info, data, pos, len) return string.unpack('>i8', data, pos) end,
	uint8 = function(blob_info, data, pos, len) return string.unpack('>I1', data, pos) end,
	uint16 = function(blob_info, data, pos, len) return string.unpack('>I2', data, pos) end,
	uint32 = function(blob_info, data, pos, len) return string.unpack('>I4', data, pos) end,
	uint64 = function(blob_info, data, pos, len) return string.unpack('>I8', data, pos) end,
	double = function(blob_info, data, pos, len) return string.unpack('>d', data, pos) end,
	nested = function(blob_info, data, pos, len)
		if pos and pos ~= 1 then
			data = string.sub(data, pos, pos + len - 1)
		end
		local blobs = {}
		local ipos = 1
		while string.len(data) > ipos + blob.ATTR_ALIGN do
			local b = blob:parse(blob_info, data, ipos)
			table.insert(blobs, b)
			ipos = ipos + b:pad_len()
		end
		return blobs
	end,
	string = function(blob_info, data, pos, len)
		if not pos and not len then
			--print('string unpack', data)
			return data
		end
		local pos = pos or 1
		local end_pos = len and (pos + len - 1) or nil
		return string.sub(data, pos, end_pos - 1)
	end,
	raw = function(blob_info, data, pos, len)
		if not pos and not len then
			return data
		end
		local pos = pos or 1
		local end_pos = len and (pos + len - 1) or nil
		return string.sub(data, pos, end_pos)
	end
}

local blob_type_pack = {
	bool = function(blob_info, val) return string.pack('>I1', val == true and 1 or 0) end,
	int8 = function(blob_info, val) return string.pack('>i1', val) end,
	int16 = function(blob_info, val) return string.pack('>i2', val) end,
	int32 = function(blob_info, val) return string.pack('>i4', val) end,
	int64 = function(blob_info, val) return string.pack('>i8', val) end,
	uint8 = function(blob_info, val) return string.pack('>I1', val) end,
	uint16 = function(blob_info, val) return string.pack('>I2', val) end,
	uint32 = function(blob_info, val) return string.pack('>I4', val) end,
	uint64 = function(blob_info, val) return string.pack('>I8', val) end,
	double = function(blob_info, val) return string.pack('>d', val) end,
	nested = function(blob_info, val)
		if type(val) ~= 'table' then
			return val
		end
		local list = {}
		for _, v in ipairs(val) do
			table.insert(list, tostring(v))
		end
		return table.concat(list)
	end,
	string = function(blob_info, val)
		return val .. '\0'
	end,
	raw = function(blob_info, val)
		return val
	end,
}

blob.static.ATTR_ID_MASK = 0x7f000000
blob.static.ATTR_ID_SHIFT = 24
blob.static.ATTR_LEN_MASK = 0x00ffffff
blob.static.ATTR_ALIGN = 4
blob.static.ATTR_EXTENDED = 0x80000000
blob.static.ATTR_HDR_LEN = 4

function blob.static:parse(blob_info, raw, pos, only_hdr)
	--print('parse blob', basexx.to_hex(string.sub(raw, pos or 1)))
	local self = self:allocate()
	local pos = pos or 1
	local id_len = string.unpack('>I4', raw, pos)

	self._id = (id_len & blob.ATTR_ID_MASK) >> blob.ATTR_ID_SHIFT
	self._ext = (id_len & blob.ATTR_EXTENDED) == blob.ATTR_EXTENDED
	self._len = (id_len & blob.ATTR_LEN_MASK) - blob.ATTR_HDR_LEN

	self._blob_info = blob_info
	local info = self._blob_info and self._blob_info[self._id] or nil

	--local info_type = info and get_type(info.type) or 'N/A'
	--print('blob parse result id:'..self._id.. "\text:"..tostring(self._ext).."\tlen:"..self._len.."\tinfo:"..info_type)

	if only_hdr then
		-- for reading socket hack
		return self
	end

	--local info_type = info and get_type(info.type) or 'N/A'
	--print('blob parse result id:'..self._id.. "\text:"..tostring(self._ext).."\tlen:"..self._len.."\tinfo:"..info_type)

	-- decode data
	if self._len > 0 then
		--local pad_len = self:pad_len()
		local raw_len = self:raw_len()

		local start_pos = pos + blob.ATTR_HDR_LEN
		local end_pos = pos + raw_len - 1
		--print('Blob[data]: ', basexx.to_hex(string.sub(raw, pos, end_pos)))
		assert(string.len(raw) >= end_pos, 'raw string len:'..string.len(raw)..' required: '..end_pos)

		local raw_data = string.sub(raw, start_pos, end_pos)
		if raw_data and info and not self._ext then
			local unpack = info.unpack or blob_type_unpack[get_type(info.type)]
			self._data = unpack and unpack(self._blob_info, raw_data, 1, self._len) or raw_data
		else
			self._data = raw_data
		end
	else
		--local end_pos = pos + blob.HRD_LEN - 1
		--print('Blob[no_data]: ', basexx.to_hex(string.sub(raw, pos, end_pos)))
	end

	return self
end

function blob:initialize(blob_info, id, len, data, ext)
	self._blob_info = blob_info
	self._id = id or 0
	self._len = len or 0
	self._data = data
	self._ext = ext
end

function blob:dbg_print()
	print('blob', self._id, self._len, self._ext)
end

function blob:data()
	return self._data
end

function blob:set_data(data)
	self._data = data
end

function blob:id()
	return self._id
end

function blob:id_len()
	return ((self._id << blob.ATTR_ID_SHIFT) & blob.ATTR_ID_MASK) + self:raw_len()
end

function blob:extended()
	return self._ext
end

--[[
function blob:set_extended(ext)
	self._ext = ext
end
]]--

function blob:len()
	return self._len
end

function blob:raw_len()
	return (self._len + blob.ATTR_HDR_LEN) & blob.ATTR_LEN_MASK
end

function blob:pad_len()
	return (self:raw_len() + blob.ATTR_ALIGN - 1) & ~(blob.ATTR_ALIGN - 1)
end

function blob:pack_data()
	local raw_len = self:raw_len()
	local pad_len = self:pad_len()

	--print('blob tostring', self._id, self._len, self._ext, string.len(self._data))
	local raw_data = self._data

	local info = self._blob_info and self._blob_info[self._id] or nil
	if raw_data and info and not self._ext then
		local pack = info.pack or blob_type_pack[get_type(info.type)]
		raw_data = pack and pack(self._blob_info, raw_data) or raw_data
	end

	raw_data = raw_data or ''
	assert(raw_len - blob.ATTR_HDR_LEN == string.len(raw_data), string.format("id: %d\traw_len: %d\t raw_data_len: %d", self._id, raw_len, string.len(raw_data)))

	if pad_len > raw_len then
		raw_data = raw_data..string.rep('\0', pad_len - raw_len)
	end
	local data_len = pad_len - blob.ATTR_HDR_LEN
	assert(data_len == string.len(raw_data))
	return raw_data, data_len
end

function blob:__tostring()
	local id_len = self:id_len()
	if self._ext then
		id_len = id_len | blob.ATTR_EXTENDED
	end
	local raw_data, data_len = self:pack_data()
	--print("blob tostring", basexx.to_hex(string.pack('>I4c'..data_len, id_len, raw_data)))
	return string.pack('>I4c'..data_len, id_len, raw_data)
end

return blob
