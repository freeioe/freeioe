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

local M = {}
local M_mt = { __metatable = {}, __index = M }

M.digest_size = 20
M.block_size = 64

local function rotate_left(x, n)
    return (x << n) | (x >> (32-n))
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._H0 = u32(0x67452301)
    o._H1 = u32(0xEFCDAB89)
    o._H2 = u32(0x98BADCFE)
    o._H3 = u32(0x10325476)
    o._H4 = u32(0xC3D2E1F0)
    o._len = 0
    o._data = ""

    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = M:new()
    o._H0 = self._H0:copy()
    o._H1 = self._H1:copy()
    o._H2 = self._H2:copy()
    o._H3 = self._H3:copy()
    o._H4 = self._H4:copy()
    o._data = self._data
    o._len = self._len
    return o
end

function M:update(data)
    local K0 = u32(0x5A827999)
    local K1 = u32(0x6ED9EBA1)
    local K2 = u32(0x8F1BBCDC)
    local K3 = u32(0xCA62C1D6)
    local W
    local temp
    local A
    local B
    local C
    local D
    local E

    if data == nil then
        data = ""
    end

    data = tostring(data)
    self._len = self._len + #data
    self._data = self._data .. data

    while #self._data >= 64 do
        W = {}
        for i=1,64,4 do
            local j = #W+1
            W[j] = u32(string.byte(self._data, i)) << 24
            W[j] = W[j] | u32(string.byte(self._data, i+1)) << 16
            W[j] = W[j] | u32(string.byte(self._data, i+2)) << 8
            W[j] = W[j] | u32(string.byte(self._data, i+3))
        end

        for i=17,80 do
            W[i] = rotate_left(W[i-3] ~ W[i-8] ~ W[i-14] ~ W[i-16], 1)
        end

        A = self._H0
        B = self._H1
        C = self._H2
        D = self._H3
        E = self._H4

        for i=1,20 do
            temp = rotate_left(A, 5) + ((B & C) | ((~B) & D)) + E + W[i] + K0
            E = D
            D = C
            C = rotate_left(B, 30)
            B = A
            A = temp
        end

        for i=21,40 do
            temp = rotate_left(A, 5) + (B ~ C ~ D) + E + W[i] + K1
            E = D
            D = C
            C = rotate_left(B, 30)
            B = A
            A = temp
        end

        for i=41,60 do
            temp = rotate_left(A, 5) + ((B & C) | (B & D) | (C & D)) + E + W[i] + K2
            E = D
            D = C
            C = rotate_left(B, 30)
            B = A
            A = temp
        end

        for i=61,80 do
            temp = rotate_left(A, 5) + (B ~ C ~ D) + E + W[i] + K3
            E = D
            D = C
            C = rotate_left(B, 30)
            B = A
            A = temp
        end

        self._H0 = self._H0 + A
        self._H1 = self._H1 + B
        self._H2 = self._H2 + C
        self._H3 = self._H3 + D
        self._H4 = self._H4 + E

        self._data = self._data:sub(65, #self._data)
    end
end

function M:digest()
    local final
    local data
    local len = 0
    local padlen = 0

    final = self:copy()

    padlen = final._len % 64
    if padlen < 56 then
        padlen = 56 - padlen
    else
        padlen = 120 - padlen
    end

    len = final._len * 8
    data = string.char(1<<7) ..
        string.rep(string.char(0), padlen-1) ..
        string.char(len >> 56 & 0xFF) ..
        string.char(len >> 48 & 0xFF) ..
        string.char(len >> 40 & 0xFF) ..
        string.char(len >> 32 & 0xFF) ..
        string.char(len >> 24 & 0xFF) ..
        string.char(len >> 16 & 0xFF) ..
        string.char(len >> 8 & 0xFF) ..
        string.char(len & 0xFF)

    final:update(data)

    return final._H0:asbytestring() ..
        final._H1:asbytestring() ..
        final._H2:asbytestring() ..
        final._H3:asbytestring() ..
        final._H4:asbytestring()
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
