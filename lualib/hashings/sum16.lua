
local string = require("string")
local u32 = require("nums.uintn").u32
local u16 = require("nums.uintn").u16

local M = {}
local M_mt = { __metatable = {}, __index = M }

M.digest_size = 2
M.block_size = 2

local function digest_int(cs)
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)
    o._sum = u32(0)
    
    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = M:new()
    o._sum = self._sum:copy()
    return o
end

function M:update(data)
	if ((#data) % 2) == 1 then
		data = data..string.char(0)
	end

	for i = 1, #data, 2 do
		self._sum = self._sum + (string.byte(data, i) * 256 + string.byte(data, i + 1))
	end
end

function M:digest()
	local sum = self._sum:copy()
	while (sum >> 16) > 0 do
		sum = (sum & 0xFFFF) + (sum >> 16)
	end

    return (~u16(sum)):asbytestring()
end

function M:hexdigest()
    local h
    local out = {}

    h = self:digest()
    for i=1,#h do
        out[i] = string.format("%02X", string.byte(h, i))
    end
    return table.concat(out)
end

return M
