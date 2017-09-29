-- Copyright (c) 2016 John Schember <john@nachtimwald.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

local string = require("string")
local u64 = require("nums.uintb").u64

local M = {}
local M_mt = { __metatable = {}, __index = M }

--[[
for i=0,4 do
    print(((i+4)%5), ((i+1)%5))
end
]]--
-- idx + 1 for lua offsets starting with 1
local theta_idxs = {
    { 5, 2 }, { 1, 3 }, { 2, 4 }, { 3, 5 }, { 4, 1 }
}

--[[
local x = 1
local y = 0
local Y
local r
for i=1,24 do
    Y = (2*x)+(3*y)
    x = y
    y = Y % 5
    r = x+(5*y)
    print(r)
end
]]--
-- idx + 1 for lua offsets starting with 1
local rhopi_idxs = {
    11, 8, 12, 18, 19, 4, 6, 17, 9, 22, 25, 5,
    16, 24, 20, 14, 13, 3, 21, 15, 23, 10, 7, 2
}
--
--[[
local r = 0
for i=0,23 do
    r = r+i+1
    print(r%64)
end
]]--
local rotation_constants = {
    1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
    27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44
}

--[[
for i=0,24,5 do
    for j=0,4 do
        print(((j+1)%5)+i, ((j+2)%5)+i)
    end
end
]]--
-- idx + 1 for lua offsets starting with 1
local chi_idxs = {
    { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 1 }, { 1, 2 },
    { 7, 8 }, { 8, 9 }, { 9, 10 }, { 10, 6 }, { 6, 7 },
    { 12, 13 }, { 13, 14 }, { 14, 15 }, { 15, 11 }, { 11, 12 },
    { 17, 18 }, { 18, 19 }, { 19, 20 }, { 20, 16 }, { 16, 17 },
    { 22, 23 }, { 23, 24 }, { 24, 25 }, { 25, 21 }, { 21, 22 }
}

--[[
local R = u8(1)
local b
for i=1,24 do
    b = u64(0)
    for j=0,6 do
        R = ((R<<1) ~ (113 * (R>>7)))
        if R & 2 ~= u8(0) then
            b = b ~ u64(1)<<((1<<j)-1)
        end
        print(b:ashex())
    end
end
]]--
local round_constants = {
    u64("0x1"), u64("0x8082"), u64("0x800000000000808A"), u64("0x8000000080008000"),
    u64("0x808B"), u64("0x80000001"), u64("0x8000000080008081"), u64("0x8000000000008009"),
    u64("0x8A"), u64("0x88"), u64("0x80008009"), u64("0x8000000A"),
    u64("0x8000808B"), u64("0x800000000000008B"), u64("0x8000000000008089"), u64("0x8000000000008003"),
    u64("0x8000000000008002"), u64("0x8000000000000080"), u64("0x800A"), u64("0x800000008000000A"),
    u64("0x8000000080008081"), u64("0x8000000000008080"), u64("0x80000001"), u64("0x8000000080008008")
}

local function rotate_left(x, n)
    return (x << n) | (x >> (64-n))
end

local function load_block(cs)
    local j
    local k

    for i=1,cs._block_size,8 do
        j = i//8+1
        k = ((i//8)*8)+1
        cs._s[j] = cs._s[j] ~ 
            (u64(string.byte(cs._data, k)) |
            u64(string.byte(cs._data, k+1)) << 8 |
            u64(string.byte(cs._data, k+2)) << 16 |
            u64(string.byte(cs._data, k+3)) << 24 |
            u64(string.byte(cs._data, k+4)) << 32 |
            u64(string.byte(cs._data, k+5)) << 40 |
            u64(string.byte(cs._data, k+6)) << 48 |
            u64(string.byte(cs._data, k+7)) << 56)
    end
    cs._data = cs._data:sub(cs._block_size+1)
end

local function permute_theta(s)
    local B = {}
    local t

    for i=1,5 do
        B[i] = s[i] ~ s[i+5] ~ s[i+10] ~ s[i+15] ~ s[i+20]
    end

    for i=1,5 do
        t = B[theta_idxs[i][1]] ~ rotate_left(B[theta_idxs[i][2]], 1)
        for j=i,25,5 do
            s[j] = s[j] ~ t
        end
    end
end

local function permute_rho_pi(s)
    local b
    local t

    t = s[2]:copy()
    for i=1,24 do
        b = s[rhopi_idxs[i]]
        s[rhopi_idxs[i]] = rotate_left(t, rotation_constants[i])
        t = b
    end
end

local function permute_chi(s)
    local B = {}

    for i=1,25 do
        B[i] = s[i]:copy()
    end

    for i=1,25 do
        s[i] = s[i] ~ (~B[chi_idxs[i][1]] & B[chi_idxs[i][2]])
    end
end

local function permute_iota(s, n)
    s[1] = s[1] ~ round_constants[n]
end

function M:new(block_size, digest_size, data)
    if self ~= M then
        return nil, "First argument must be self"
    end

    if block_size > 200 then
        return nil, "Invalid block size"
    end

    local o = setmetatable({}, M_mt)

    o._block_size = block_size
    o._digest_size = digest_size
    o._data = ""

    o._s = {}
    for i=1,25 do
        o._s[i] = u64(0)
    end

    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = setmetatable({}, M_mt)

    o._block_size = self._block_size
    o._digest_size = self._digest_size
    o._data = self._data

    o._s = {}
    for i=1,25 do
        o._s[i] = self._s[i]:copy()
    end

    return o
end

function M:update(data)
    if data == nil then
        data = ""
    end

    data = tostring(data)
    self._data = self._data .. data

    while #self._data >= self._block_size do
        load_block(self)
        for i=1,24 do
            permute_theta(self._s)
            permute_rho_pi(self._s)
            permute_chi(self._s)
            permute_iota(self._s, i)
        end
    end
end

function M:digest()
    local final
    local data
    local out = {}

    final = self:copy()

    -- Pad
    if #final._data == final._block_size - 1 then
        data = string.char(0x06|0x80)
    else
        data = string.char(0x06) .. string.rep(string.char(0), final._block_size - #final._data - 2) .. string.char(0x80)
    end

    final:update(data)

    -- Squeeze
    for i=1,final._digest_size//8 do
        out[i] = final._s[i]:swape():asbytestring()
    end

    return table.concat(out)
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
