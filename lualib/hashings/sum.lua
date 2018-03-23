
local string = require("string")
local u8 = require("nums.uintn").u8

local M = {}
local M_mt = { __metatable = {}, __index = M }

M.digest_size = 1
M.block_size = 1

local function digest_int(cs)
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)
    o._sum = u8(0)
    
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
	local sum = u8(0)
	for i = 1, #data do
		sum = sum + string.byte(data, i)
	end
	self._sum = sum:copy()
end

function M:digest()
    return self._sum:asbytestring()
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
