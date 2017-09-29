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

M.digest_size = 32
M.block_size = 64

local K = {
    u32(0x428A2F98), u32(0x71374491), u32(0xB5C0FBCF), u32(0xE9B5DBA5),
    u32(0x3956C25B), u32(0x59F111F1), u32(0x923F82A4), u32(0xAB1C5ED5),
    u32(0xD807AA98), u32(0x12835B01), u32(0x243185BE), u32(0x550C7DC3),
    u32(0x72BE5D74), u32(0x80DEB1FE), u32(0x9BDC06A7), u32(0xC19BF174),
    u32(0xE49B69C1), u32(0xEFBE4786), u32(0x0FC19DC6), u32(0x240CA1CC),
    u32(0x2DE92C6F), u32(0x4A7484AA), u32(0x5CB0A9DC), u32(0x76F988DA),
    u32(0x983E5152), u32(0xA831C66D), u32(0xB00327C8), u32(0xBF597FC7),
    u32(0xC6E00BF3), u32(0xD5A79147), u32(0x06CA6351), u32(0x14292967),
    u32(0x27B70A85), u32(0x2E1B2138), u32(0x4D2C6DFC), u32(0x53380D13),
    u32(0x650A7354), u32(0x766A0ABB), u32(0x81C2C92E), u32(0x92722C85),
    u32(0xA2BFE8A1), u32(0xA81A664B), u32(0xC24B8B70), u32(0xC76C51A3),
    u32(0xD192E819), u32(0xD6990624), u32(0xF40E3585), u32(0x106AA070),
    u32(0x19A4C116), u32(0x1E376C08), u32(0x2748774C), u32(0x34B0BCB5),
    u32(0x391C0CB3), u32(0x4ED8AA4A), u32(0x5B9CCA4F), u32(0x682E6FF3),
    u32(0x748F82EE), u32(0x78A5636F), u32(0x84C87814), u32(0x8CC70208),
    u32(0x90BEFFFA), u32(0xA4506CEB), u32(0xBEF9A3F7), u32(0xC67178F2)
}

local function rotate_right(x, n)
    return (x >> n) | (x << (32-n))
end

local function CH(x, y, z)
    return (x & y) ~ ((~x) & z)
end

local function MAJ(x, y, z)
    return (x & y) ~ ( x & z) ~ (y & z)
end

local function BSIG0(x)
    return rotate_right(x, 2) ~ rotate_right(x, 13) ~ rotate_right(x, 22)
end

local function BSIG1(x)
    return rotate_right(x, 6) ~ rotate_right(x, 11) ~ rotate_right(x, 25)
end

local function SSIG0(x)
    return rotate_right(x, 7) ~ rotate_right(x, 18) ~ (x >> 3)
end

local function SSIG1(x)
    return rotate_right(x, 17) ~ rotate_right(x, 19) ~ (x >> 10)
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._H0 = u32(0x6A09E667)
    o._H1 = u32(0xBB67AE85)
    o._H2 = u32(0x3C6EF372)
    o._H3 = u32(0xA54FF53A)
    o._H4 = u32(0x510E527F)
    o._H5 = u32(0x9B05688C)
    o._H6 = u32(0x1F83D9AB)
    o._H7 = u32(0x5BE0CD19)
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
    o._H5 = self._H5:copy()
    o._H6 = self._H6:copy()
    o._H7 = self._H7:copy()
    o._data = self._data
    o._len = self._len
    return o
end

function M:update(data)
    local W
    local temp1
    local temp2
    local a
    local b
    local c
    local d
    local e
    local f
    local g
    local h

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
        self._data = self._data:sub(65, #self._data)

        for i=17,64 do
            W[i] = SSIG1(W[i-2]) + W[i-7] + SSIG0(W[i-15]) + W[i-16]
        end

        a = self._H0
        b = self._H1
        c = self._H2
        d = self._H3
        e = self._H4
        f = self._H5
        g = self._H6
        h = self._H7

        for i=1,64 do
            temp1 = h + BSIG1(e) + CH(e, f, g) + K[i] + W[i]
            temp2 = BSIG0(a) + MAJ(a, b, c)
            h = g
            g = f
            f = e
            e = d + temp1
            d = c
            c = b
            b = a
            a = temp1 + temp2
        end

        self._H0 = self._H0 + a
        self._H1 = self._H1 + b
        self._H2 = self._H2 + c
        self._H3 = self._H3 + d
        self._H4 = self._H4 + e
        self._H5 = self._H5 + f
        self._H6 = self._H6 + g
        self._H7 = self._H7 + h
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
        final._H4:asbytestring() ..
        final._H5:asbytestring() ..
        final._H6:asbytestring() ..
        final._H7:asbytestring()
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
