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
local u32 = require("nums.uintn").u32
local u8 = require("nums.uintn").u8

local M = {}
local M_mt = { __metatable = {}, __index = M }

M.digest_size = 32
M.block_size = 64

local IV = {
    u32(0x6A09E667), u32(0xBB67AE85), u32(0x3C6EF372), u32(0xA54FF53A),
    u32(0x510E527F), u32(0x9B05688C), u32(0x1F83D9AB), u32(0x5BE0CD19)
}

local sigma = {
    { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
    { 15, 11, 5, 9, 10, 16, 14, 7, 2, 13, 1, 3, 12, 8, 6, 4 },
    { 12, 9, 13, 1, 6, 3, 16, 14, 11, 15, 4, 7, 8, 2, 10, 5 },
    { 8, 10, 4, 2, 14, 13, 12, 15, 3, 7, 6, 11, 5, 1, 16, 9 },
    { 10, 1, 6, 8, 3, 5, 11, 16, 15, 2, 12, 13, 7, 9, 4, 14 },
    { 3, 13, 7, 11, 1, 12, 9, 4, 5, 14, 8, 6, 16, 15, 2, 10 },
    { 13, 6, 2, 16, 15, 14, 5, 11, 1, 8, 7, 4, 10, 3, 9, 12 },
    { 14, 12, 8, 15, 13, 2, 4, 10, 6, 1, 16, 5, 9, 7, 3, 11 },
    { 7, 16, 15, 10, 12, 4, 1, 9, 13, 3, 14, 8, 2, 5, 11, 6 },
    { 11, 3, 9, 5, 8, 7, 2, 6, 16, 12, 10, 15, 4, 13, 14, 1 }
}

local function rotate_right(x, n)
    return (x >> n) | (x << (32-n))
end

local function increment_counter(cs, len)
    cs._t0 = cs._t0 + len
    if cs._t0 < len then
        cs._t1 = cs._t1 + 1
    end
end

local function G(r, i, m, a, b, c, d)
    a = a + b + m[sigma[r+1][2*i+1]]
    d = rotate_right(d ~ a, 16)
    c = c + d
    b = rotate_right(b ~ c, 12)
    a = a + b + m[sigma[r+1][2*i+2]]
    d = rotate_right(d ~ a, 8)
    c = c + d
    b = rotate_right(b ~ c, 7)
    return a, b, c, d
end

local function ROUND(r, m, v)
    v[1], v[5], v[9], v[13] = G(r ,0, m, v[1], v[5], v[9], v[13])
    v[2], v[6], v[10], v[14] = G(r, 1, m, v[2], v[6], v[10], v[14])
    v[3], v[7], v[11], v[15] = G(r, 2, m, v[3], v[7], v[11], v[15])
    v[4], v[8], v[12], v[16] = G(r, 3, m, v[4], v[8], v[12], v[16])
    v[1], v[6], v[11], v[16] = G(r, 4, m, v[1], v[6], v[11], v[16])
    v[2], v[7], v[12], v[13] = G(r, 5, m, v[2], v[7], v[12], v[13])
    v[3], v[8], v[9], v[14] = G(r, 6, m, v[3], v[8], v[9], v[14])
    v[4], v[5], v[10], v[15] = G(r, 7, m, v[4], v[5], v[10], v[15])
end

local function compress(cs)
    local v = {}
    local m = {}

    if #cs._data < 64 then
        return
    end

    for j=1,64,4 do
        m[#m+1] = u32(string.byte(cs._data, j+3) << 24 |
        string.byte(cs._data, j+2) << 16 |
        string.byte(cs._data, j+1) << 8 |
        string.byte(cs._data, j))
    end
    cs._data = cs._data:sub(65, #cs._data)

    for i=1,8 do
        v[i] = cs._h[i]:copy()
    end
    v[9] = IV[1]:copy()
    v[10] = IV[2]:copy()
    v[11] = IV[3]:copy()
    v[12] = IV[4]:copy()
    v[13] = cs._t0 ~ IV[5]
    v[14] = cs._t1 ~ IV[6]
    if cs._last then
        v[15] = u32(0xFFFFFFFF) ~ IV[7]
    else
        v[15] = IV[7]:copy()
    end
    v[16] = IV[8]:copy()

    ROUND(0, m, v)
    ROUND(1, m, v)
    ROUND(2, m, v)
    ROUND(3, m, v)
    ROUND(4, m, v)
    ROUND(5, m, v)
    ROUND(6, m, v)
    ROUND(7, m, v)
    ROUND(8, m, v)
    ROUND(9, m, v)

    for i=1,8 do
        cs._h[i] = cs._h[i] ~ v[i] ~ v[i+8]
    end
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._h = {}
    for i=1,8 do
        o._h[i] = IV[i]:copy()
    end
    -- XOR in param block. We don't support salt for
    -- personal parameters so this ends up being a constant.
    o._h[1] = o._h[1] ~ 16842784

    o._last = false
    o._t0 = u32(0)
    o._t1 = u32(0)
    o._data = ""

    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = M()
    for i=1,8 do
        o._h[i] = self._h[i]:copy()
    end
    o._last = self._last
    o._t0 = self._t0:copy()
    o._t1 = self._t1:copy()
    o._data = self._data
    return o
end

function M:update(data)
    if data == nil then
        data = ""
    end

    data = tostring(data)
    self._data = self._data .. data

    -- Update always leaves at least 1 byte for final.
    while #self._data > 64 do
        increment_counter(self, 64)
        compress(self)
    end
end

function M:digest()
    local final
    local out = {}

    final = self:copy()

    increment_counter(final, #final._data)
    final._last = true
    final._data = final._data .. string.rep(string.char(0), 64 - #final._data)
    compress(final)

    for i=1,#final._h do
        out[i] = final._h[i]:swape():asbytestring()
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
