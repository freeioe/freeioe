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

local function F(X, Y, Z)
    return X ~ Y ~ Z
end

local function G(X, Y, Z)
    return (X & Y) | (~X & Z)
end

local function H(X, Y, Z)
    return (X | ~Y) ~ Z
end

local function I(X, Y, Z)
    return (X & Z) | (Y & ~Z)
end

local function J(X, Y, Z)
    return X ~ (Y | ~Z)
end

local function rotate_left(x, n)
    return (x << n) | (x >> (32-n))
end

local function run_step(f, a, b, c, d, e, x, s, ac)
    a = a + f(b, c, d) + x + ac
    a = rotate_left(a, s) + e
    return a, rotate_left(c, 10)
end

local function transform(A, B, C, D, E, X)
    local a = A
    local b = B
    local c = C
    local d = D
    local e = E
    local aa = A
    local bb = B
    local cc = C
    local dd = D
    local ee = E

    -- Round 1
    a, c = run_step(F, a, b, c, d, e, X[1], 11, 0) 
    e, b = run_step(F, e, a, b, c, d, X[2], 14, 0)
    d, a = run_step(F, d, e, a, b, c, X[3], 15, 0)
    c, e = run_step(F, c, d, e, a, b, X[4], 12, 0)
    b, d = run_step(F, b, c, d, e, a, X[5], 5, 0)
    a, c = run_step(F, a, b, c, d, e, X[6], 8, 0)
    e, b = run_step(F, e, a, b, c, d, X[7], 7, 0)
    d, a = run_step(F, d, e, a, b, c, X[8], 9, 0)
    c, e = run_step(F, c, d, e, a, b, X[9], 11, 0)
    b, d = run_step(F, b, c, d, e, a, X[10], 13, 0)
    a, c = run_step(F, a, b, c, d, e, X[11], 14, 0)
    e, b = run_step(F, e, a, b, c, d, X[12], 15, 0)
    d, a = run_step(F, d, e, a, b, c, X[13], 6, 0)
    c, e = run_step(F, c, d, e, a, b, X[14], 7, 0)
    b, d = run_step(F, b, c, d, e, a, X[15], 9, 0)
    a, c = run_step(F, a, b, c, d, e, X[16], 8, 0)

    -- Round 2
    e, b = run_step(G, e, a, b, c, d, X[8], 7, 0x5A827999)
    d, a = run_step(G, d, e, a, b, c, X[5], 6, 0x5A827999)
    c, e = run_step(G, c, d, e, a, b, X[14], 8, 0x5A827999)
    b, d = run_step(G, b, c, d, e, a, X[2], 13, 0x5A827999)
    a, c = run_step(G, a, b, c, d, e, X[11], 11, 0x5A827999)
    e, b = run_step(G, e, a, b, c, d, X[7], 9, 0x5A827999)
    d, a = run_step(G, d, e, a, b, c, X[16], 7, 0x5A827999)
    c, e = run_step(G, c, d, e, a, b, X[4], 15, 0x5A827999)
    b, d = run_step(G, b, c, d, e, a, X[13], 7, 0x5A827999)
    a, c = run_step(G, a, b, c, d, e, X[1], 12, 0x5A827999)
    e, b = run_step(G, e, a, b, c, d, X[10], 15, 0x5A827999)
    d, a = run_step(G, d, e, a, b, c, X[6], 9, 0x5A827999)
    c, e = run_step(G, c, d, e, a, b, X[3], 11, 0x5A827999)
    b, d = run_step(G, b, c, d, e, a, X[15], 7, 0x5A827999)
    a, c = run_step(G, a, b, c, d, e, X[12], 13, 0x5A827999)
    e, b = run_step(G, e, a, b, c, d, X[9], 12, 0x5A827999)

    -- Round 3
    d, a = run_step(H, d, e, a, b, c, X[4], 11, 0x6ED9EBA1)
    c, e = run_step(H, c, d, e, a, b, X[11], 13, 0x6ED9EBA1)
    b, d = run_step(H, b, c, d, e, a, X[15], 6, 0x6ED9EBA1)
    a, c = run_step(H, a, b, c, d, e, X[5], 7, 0x6ED9EBA1)
    e, b = run_step(H, e, a, b, c, d, X[10], 14, 0x6ED9EBA1)
    d, a = run_step(H, d, e, a, b, c, X[16], 9, 0x6ED9EBA1)
    c, e = run_step(H, c, d, e, a, b, X[9], 13, 0x6ED9EBA1)
    b, d = run_step(H, b, c, d, e, a, X[2], 15, 0x6ED9EBA1)
    a, c = run_step(H, a, b, c, d, e, X[3], 14, 0x6ED9EBA1)
    e, b = run_step(H, e, a, b, c, d, X[8], 8, 0x6ED9EBA1)
    d, a = run_step(H, d, e, a, b, c, X[1], 13, 0x6ED9EBA1)
    c, e = run_step(H, c, d, e, a, b, X[7], 6, 0x6ED9EBA1)
    b, d = run_step(H, b, c, d, e, a, X[14], 5, 0x6ED9EBA1)
    a, c = run_step(H, a, b, c, d, e, X[12], 12, 0x6ED9EBA1)
    e, b = run_step(H, e, a, b, c, d, X[6], 7, 0x6ED9EBA1)
    d, a = run_step(H, d, e, a, b, c, X[13], 5, 0x6ED9EBA1)

    -- Round 4
    c, e = run_step(I, c, d, e, a, b, X[2], 11, 0x8F1BBCDC)
    b, d = run_step(I, b, c, d, e, a, X[10], 12, 0x8F1BBCDC)
    a, c = run_step(I, a, b, c, d, e, X[12], 14, 0x8F1BBCDC)
    e, b = run_step(I, e, a, b, c, d, X[11], 15, 0x8F1BBCDC)
    d, a = run_step(I, d, e, a, b, c, X[1], 14, 0x8F1BBCDC)
    c, e = run_step(I, c, d, e, a, b, X[9], 15, 0x8F1BBCDC)
    b, d = run_step(I, b, c, d, e, a, X[13], 9, 0x8F1BBCDC)
    a, c = run_step(I, a, b, c, d, e, X[5], 8, 0x8F1BBCDC)
    e, b = run_step(I, e, a, b, c, d, X[14], 9, 0x8F1BBCDC)
    d, a = run_step(I, d, e, a, b, c, X[4], 14, 0x8F1BBCDC)
    c, e = run_step(I, c, d, e, a, b, X[8], 5, 0x8F1BBCDC)
    b, d = run_step(I, b, c, d, e, a, X[16], 6, 0x8F1BBCDC)
    a, c = run_step(I, a, b, c, d, e, X[15], 8, 0x8F1BBCDC)
    e, b = run_step(I, e, a, b, c, d, X[6], 6, 0x8F1BBCDC)
    d, a = run_step(I, d, e, a, b, c, X[7], 5, 0x8F1BBCDC)
    c, e = run_step(I, c, d, e, a, b, X[3], 12, 0x8F1BBCDC)

    -- Round 5
    b, d = run_step(J, b, c, d, e, a, X[5], 9, 0xA953FD4E)
    a, c = run_step(J, a, b, c, d, e, X[1], 15, 0xA953FD4E)
    e, b = run_step(J, e, a, b, c, d, X[6], 5, 0xA953FD4E)
    d, a = run_step(J, d, e, a, b, c, X[10], 11, 0xA953FD4E)
    c, e = run_step(J, c, d, e, a, b, X[8], 6, 0xA953FD4E)
    b, d = run_step(J, b, c, d, e, a, X[13], 8, 0xA953FD4E)
    a, c = run_step(J, a, b, c, d, e, X[3], 13, 0xA953FD4E)
    e, b = run_step(J, e, a, b, c, d, X[11], 12, 0xA953FD4E)
    d, a = run_step(J, d, e, a, b, c, X[15], 5, 0xA953FD4E)
    c, e = run_step(J, c, d, e, a, b, X[2], 12, 0xA953FD4E)
    b, d = run_step(J, b, c, d, e, a, X[4], 13, 0xA953FD4E)
    a, c = run_step(J, a, b, c, d, e, X[9], 14, 0xA953FD4E)
    e, b = run_step(J, e, a, b, c, d, X[12], 11, 0xA953FD4E)
    d, a = run_step(J, d, e, a, b, c, X[7], 8, 0xA953FD4E)
    c, e = run_step(J, c, d, e, a, b, X[16], 5, 0xA953FD4E)
    b, d = run_step(J, b, c, d, e, a, X[14], 6, 0xA953FD4E)

    -- Parallel Round 1
    aa, cc = run_step(J, aa, bb, cc, dd, ee, X[6], 8, 0x50A28BE6)
    ee, bb = run_step(J, ee, aa, bb, cc, dd, X[15], 9, 0x50A28BE6)
    dd, aa = run_step(J, dd, ee, aa, bb, cc, X[8], 9, 0x50A28BE6)
    cc, ee = run_step(J, cc, dd, ee, aa, bb, X[1], 11, 0x50A28BE6)
    bb, dd = run_step(J, bb, cc, dd, ee, aa, X[10], 13, 0x50A28BE6)
    aa, cc = run_step(J, aa, bb, cc, dd, ee, X[3], 15, 0x50A28BE6)
    ee, bb = run_step(J, ee, aa, bb, cc, dd, X[12], 15, 0x50A28BE6)
    dd, aa = run_step(J, dd, ee, aa, bb, cc, X[5], 5, 0x50A28BE6)
    cc, ee = run_step(J, cc, dd, ee, aa, bb, X[14], 7, 0x50A28BE6)
    bb, dd = run_step(J, bb, cc, dd, ee, aa, X[7], 7, 0x50A28BE6)
    aa, cc = run_step(J, aa, bb, cc, dd, ee, X[16], 8, 0x50A28BE6)
    ee, bb = run_step(J, ee, aa, bb, cc, dd, X[9], 11, 0x50A28BE6)
    dd, aa = run_step(J, dd, ee, aa, bb, cc, X[2], 14, 0x50A28BE6)
    cc, ee = run_step(J, cc, dd, ee, aa, bb, X[11], 14, 0x50A28BE6)
    bb, dd = run_step(J, bb, cc, dd, ee, aa, X[4], 12, 0x50A28BE6)
    aa, cc = run_step(J, aa, bb, cc, dd, ee, X[13], 6, 0x50A28BE6)

    -- Parallel Round 2
    ee, bb = run_step(I, ee, aa, bb, cc, dd, X[7], 9, 0x5C4DD124) 
    dd, aa = run_step(I, dd, ee, aa, bb, cc, X[12], 13, 0x5C4DD124)
    cc, ee = run_step(I, cc, dd, ee, aa, bb, X[4], 15, 0x5C4DD124)
    bb, dd = run_step(I, bb, cc, dd, ee, aa, X[8], 7, 0x5C4DD124)
    aa, cc = run_step(I, aa, bb, cc, dd, ee, X[1], 12, 0x5C4DD124)
    ee, bb = run_step(I, ee, aa, bb, cc, dd, X[14], 8, 0x5C4DD124)
    dd, aa = run_step(I, dd, ee, aa, bb, cc, X[6], 9, 0x5C4DD124)
    cc, ee = run_step(I, cc, dd, ee, aa, bb, X[11], 11, 0x5C4DD124)
    bb, dd = run_step(I, bb, cc, dd, ee, aa, X[15], 7, 0x5C4DD124)
    aa, cc = run_step(I, aa, bb, cc, dd, ee, X[16], 7, 0x5C4DD124)
    ee, bb = run_step(I, ee, aa, bb, cc, dd, X[9], 12, 0x5C4DD124)
    dd, aa = run_step(I, dd, ee, aa, bb, cc, X[13], 7, 0x5C4DD124)
    cc, ee = run_step(I, cc, dd, ee, aa, bb, X[5], 6, 0x5C4DD124)
    bb, dd = run_step(I, bb, cc, dd, ee, aa, X[10], 15, 0x5C4DD124)
    aa, cc = run_step(I, aa, bb, cc, dd, ee, X[2], 13, 0x5C4DD124)
    ee, bb = run_step(I, ee, aa, bb, cc, dd, X[3], 11, 0x5C4DD124)

    -- Parallel Round 3
    dd, aa = run_step(H, dd, ee, aa, bb, cc, X[16], 9, 0x6D703EF3)
    cc, ee = run_step(H, cc, dd, ee, aa, bb, X[6], 7, 0x6D703EF3)
    bb, dd = run_step(H, bb, cc, dd, ee, aa, X[2], 15, 0x6D703EF3)
    aa, cc = run_step(H, aa, bb, cc, dd, ee, X[4], 11, 0x6D703EF3)
    ee, bb = run_step(H, ee, aa, bb, cc, dd, X[8], 8, 0x6D703EF3)
    dd, aa = run_step(H, dd, ee, aa, bb, cc, X[15], 6, 0x6D703EF3)
    cc, ee = run_step(H, cc, dd, ee, aa, bb, X[7], 6, 0x6D703EF3)
    bb, dd = run_step(H, bb, cc, dd, ee, aa, X[10], 14, 0x6D703EF3)
    aa, cc = run_step(H, aa, bb, cc, dd, ee, X[12], 12, 0x6D703EF3)
    ee, bb = run_step(H, ee, aa, bb, cc, dd, X[9], 13, 0x6D703EF3)
    dd, aa = run_step(H, dd, ee, aa, bb, cc, X[13], 5, 0x6D703EF3)
    cc, ee = run_step(H, cc, dd, ee, aa, bb, X[3], 14, 0x6D703EF3)
    bb, dd = run_step(H, bb, cc, dd, ee, aa, X[11], 13, 0x6D703EF3)
    aa, cc = run_step(H, aa, bb, cc, dd, ee, X[1], 13, 0x6D703EF3)
    ee, bb = run_step(H, ee, aa, bb, cc, dd, X[5], 7, 0x6D703EF3)
    dd, aa = run_step(H, dd, ee, aa, bb, cc, X[14], 5, 0x6D703EF3)

    -- Parallel Round 4
    cc, ee = run_step(G, cc, dd, ee, aa, bb, X[9], 15, 0x7A6D76E9)
    bb, dd = run_step(G, bb, cc, dd, ee, aa, X[7], 5, 0x7A6D76E9)
    aa, cc = run_step(G, aa, bb, cc, dd, ee, X[5], 8, 0x7A6D76E9)
    ee, bb = run_step(G, ee, aa, bb, cc, dd, X[2], 11, 0x7A6D76E9)
    dd, aa = run_step(G, dd, ee, aa, bb, cc, X[4], 14, 0x7A6D76E9)
    cc, ee = run_step(G, cc, dd, ee, aa, bb, X[12], 14, 0x7A6D76E9)
    bb, dd = run_step(G, bb, cc, dd, ee, aa, X[16], 6, 0x7A6D76E9)
    aa, cc = run_step(G, aa, bb, cc, dd, ee, X[1], 14, 0x7A6D76E9)
    ee, bb = run_step(G, ee, aa, bb, cc, dd, X[6], 6, 0x7A6D76E9)
    dd, aa = run_step(G, dd, ee, aa, bb, cc, X[13], 9, 0x7A6D76E9)
    cc, ee = run_step(G, cc, dd, ee, aa, bb, X[3], 12, 0x7A6D76E9)
    bb, dd = run_step(G, bb, cc, dd, ee, aa, X[14], 9, 0x7A6D76E9)
    aa, cc = run_step(G, aa, bb, cc, dd, ee, X[10], 12, 0x7A6D76E9)
    ee, bb = run_step(G, ee, aa, bb, cc, dd, X[8], 5, 0x7A6D76E9)
    dd, aa = run_step(G, dd, ee, aa, bb, cc, X[11], 15, 0x7A6D76E9)
    cc, ee = run_step(G, cc, dd, ee, aa, bb, X[15], 8, 0x7A6D76E9)

    -- Parallel Round 5
    bb, dd = run_step(F, bb, cc, dd, ee, aa, X[13], 8, 0)
    aa, cc = run_step(F, aa, bb, cc, dd, ee, X[16], 5, 0)
    ee, bb = run_step(F, ee, aa, bb, cc, dd, X[11], 12, 0)
    dd, aa = run_step(F, dd, ee, aa, bb, cc, X[5], 9, 0)
    cc, ee = run_step(F, cc, dd, ee, aa, bb, X[2], 12, 0)
    bb, dd = run_step(F, bb, cc, dd, ee, aa, X[6], 5, 0)
    aa, cc = run_step(F, aa, bb, cc, dd, ee, X[9], 14, 0)
    ee, bb = run_step(F, ee, aa, bb, cc, dd, X[8], 6, 0)
    dd, aa = run_step(F, dd, ee, aa, bb, cc, X[7], 8, 0)
    cc, ee = run_step(F, cc, dd, ee, aa, bb, X[3], 13, 0)
    bb, dd = run_step(F, bb, cc, dd, ee, aa, X[14], 6, 0)
    aa, cc = run_step(F, aa, bb, cc, dd, ee, X[15], 5, 0)
    ee, bb = run_step(F, ee, aa, bb, cc, dd, X[1], 15, 0)
    dd, aa = run_step(F, dd, ee, aa, bb, cc, X[4], 13, 0)
    cc, ee = run_step(F, cc, dd, ee, aa, bb, X[10], 11, 0)
    bb, dd = run_step(F, bb, cc, dd, ee, aa, X[12], 11, 0)

    dd = dd + c + B
    return dd, C+d+ee, D+e+aa, E+a+bb, A+b+cc
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
    o._E = u32(0xC3D2E1F0)
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
    o._E = self._E:copy()
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

        self._A, self._B, self._C, self._D, self._E = transform(self._A, self._B, self._C, self._D, self._E, X)

        self._data = self._data:sub(65, #self._data)
    end
end

local function digest_int(cs)
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
        final._D:swape():asbytestring() ..
        final._E:swape():asbytestring()
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
