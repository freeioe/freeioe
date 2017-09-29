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

M.digest_size = 16
M.block_size = 64

local function F(X, Y, Z)
    return (X & Y) | (~X & Z)
end

local function G(X, Y, Z)
    return (X & Z) | (Y & ~Z)
end

local function H(X, Y, Z)
    return X ~ Y ~ Z
end

local function I(X, Y, Z)
    return Y ~ (X | ~Z)
end

local function rotate_left(x, n)
    return (x << n) | (x >> (32-n))
end

local function run_step(f, a, b, c, d, x, s, ac)
    return rotate_left(a + f(b, c, d) + x + ac, s) + b
end

local function transform(A, B, C, D, X)
    local a = A
    local b = B
    local c = C
    local d = D

    -- Round 1
    a = run_step(F, a, b, c, d, X[1], 7, 0xD76AA478) 
    d = run_step(F, d, a, b, c, X[2], 12, 0xE8C7B756)
    c = run_step(F, c, d, a, b, X[3], 17, 0x242070DB)
    b = run_step(F, b, c, d, a, X[4], 22, 0xC1BDCEEE)
    a = run_step(F, a, b, c, d, X[5], 7, 0xF57C0FAF)
    d = run_step(F, d, a, b, c, X[6], 12, 0x4787C62A)
    c = run_step(F, c, d, a, b, X[7], 17, 0xA8304613)
    b = run_step(F, b, c, d, a, X[8], 22, 0xFD469501)
    a = run_step(F, a, b, c, d, X[9], 7, 0x698098D8)
    d = run_step(F, d, a, b, c, X[10], 12, 0x8B44F7AF)
    c = run_step(F, c, d, a, b, X[11], 17, 0xFFFF5BB1)
    b = run_step(F, b, c, d, a, X[12], 22, 0x895CD7BE)
    a = run_step(F, a, b, c, d, X[13], 7, 0x6B901122)
    d = run_step(F, d, a, b, c, X[14], 12, 0xFD987193)
    c = run_step(F, c, d, a, b, X[15], 17, 0xA679438E)
    b = run_step(F, b, c, d, a, X[16], 22, 0x49B40821)

    -- Round 2
    a = run_step(G, a, b, c, d, X[2], 5, 0xF61E2562)
    d = run_step(G, d, a, b, c, X[7], 9, 0xC040B340)
    c = run_step(G, c, d, a, b, X[12], 14, 0x265E5A51)
    b = run_step(G, b, c, d, a, X[1], 20, 0xE9B6C7AA)
    a = run_step(G, a, b, c, d, X[6], 5, 0xD62F105D)
    d = run_step(G, d, a, b, c, X[11], 9,  0x2441453)
    c = run_step(G, c, d, a, b, X[16], 14, 0xD8A1E681)
    b = run_step(G, b, c, d, a, X[5], 20, 0xE7D3FBC8)
    a = run_step(G, a, b, c, d, X[10], 5, 0x21E1CDE6)
    d = run_step(G, d, a, b, c, X[15], 9, 0xC33707D6)
    c = run_step(G, c, d, a, b, X[4], 14, 0xF4D50D87)
    b = run_step(G, b, c, d, a, X[9], 20, 0x455A14ED)
    a = run_step(G, a, b, c, d, X[14], 5, 0xA9E3E905)
    d = run_step(G, d, a, b, c, X[3], 9, 0xFCEFA3F8)
    c = run_step(G, c, d, a, b, X[8], 14, 0x676F02D9)
    b = run_step(G, b, c, d, a, X[13], 20, 0x8D2A4C8A)

    -- Round 3
    a = run_step(H, a, b, c, d, X[6], 4, 0xFFFA3942)
    d = run_step(H, d, a, b, c, X[9], 11, 0x8771F681)
    c = run_step(H, c, d, a, b, X[12], 16, 0x6D9D6122)
    b = run_step(H, b, c, d, a, X[15], 23, 0xFDE5380C)
    a = run_step(H, a, b, c, d, X[2], 4, 0xA4BEEA44)
    d = run_step(H, d, a, b, c, X[5], 11, 0x4BDECFA9)
    c = run_step(H, c, d, a, b, X[8], 16, 0xF6BB4B60)
    b = run_step(H, b, c, d, a, X[11], 23, 0xBEBFBC70)
    a = run_step(H, a, b, c, d, X[14], 4, 0x289B7EC6)
    d = run_step(H, d, a, b, c, X[1], 11, 0xEAA127FA)
    c = run_step(H, c, d, a, b, X[4], 16, 0xD4EF3085)
    b = run_step(H, b, c, d, a, X[7], 23,  0x4881D05)
    a = run_step(H, a, b, c, d, X[10], 4, 0xD9D4D039)
    d = run_step(H, d, a, b, c, X[13], 11, 0xE6DB99E5)
    c = run_step(H, c, d, a, b, X[16], 16, 0x1FA27CF8)
    b = run_step(H, b, c, d, a, X[3], 23, 0xC4AC5665)

    -- Round 4
    a = run_step(I, a, b, c, d, X[1], 6, 0xF4292244)
    d = run_step(I, d, a, b, c, X[8], 10, 0x432AFF97)
    c = run_step(I, c, d, a, b, X[15], 15, 0xAB9423A7)
    b = run_step(I, b, c, d, a, X[6], 21, 0xFC93A039)
    a = run_step(I, a, b, c, d, X[13], 6, 0x655B59C3)
    d = run_step(I, d, a, b, c, X[4], 10, 0x8F0CCC92)
    c = run_step(I, c, d, a, b, X[11], 15, 0xFFEFF47D)
    b = run_step(I, b, c, d, a, X[2], 21, 0x85845DD1)
    a = run_step(I, a, b, c, d, X[9], 6, 0x6FA87E4F)
    d = run_step(I, d, a, b, c, X[16], 10, 0xFE2CE6E0)
    c = run_step(I, c, d, a, b, X[7], 15, 0xA3014314)
    b = run_step(I, b, c, d, a, X[14], 21, 0x4E0811A1)
    a = run_step(I, a, b, c, d, X[5], 6, 0xF7537E82)
    d = run_step(I, d, a, b, c, X[12], 10, 0xBD3AF235)
    c = run_step(I, c, d, a, b, X[3], 15, 0x2AD7D2BB)
    b = run_step(I, b, c, d, a, X[10], 21, 0xEB86D391)

    return a+A, b+B, c+C, d+D
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._A = u32(0x67452301)
    o._B = u32(0xEFCDAB89)
    o._C = u32(0x98BADCFE)
    o._D = u32(0x10325476)
    o._len = 0
    o._data = ""

    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = M()
    o._A = self._A:copy()
    o._B = self._B:copy()
    o._C = self._C:copy()
    o._D = self._D:copy()
    o._data = self._data
    o._len = self._len
    return o
end

function M:update(data)
    local X

    if data == nil then
        data = ""
    end

    data = tostring(data)
    self._len = self._len + #data
    self._data = self._data .. data

    while #self._data >= 64 do
        X = {}
        for j=1,64,4 do
            X[#X+1] = string.byte(self._data, j+3) << 24 |
            string.byte(self._data, j+2) << 16 |
            string.byte(self._data, j+1) << 8 |
            string.byte(self._data, j)
        end
        self._data = self._data:sub(65, #self._data)

        self._A, self._B, self._C, self._D = transform(self._A, self._B, self._C, self._D, X)
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
        string.char(len & 0xFF) ..
        string.char(len >> 8 & 0xFF) ..
        string.char(len >> 16 & 0xFF) ..
        string.char(len >> 24 & 0xFF) ..
        string.char(len >> 32 & 0xFF) ..
        string.char(len >> 40 & 0xFF) ..
        string.char(len >> 48 & 0xFF) ..
        string.char(len >> 56 & 0xFF)

    final:update(data)

    return final._A:swape():asbytestring() ..
        final._B:swape():asbytestring() ..
        final._C:swape():asbytestring() ..
        final._D:swape():asbytestring()
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
