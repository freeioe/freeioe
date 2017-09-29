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

M.digest_size = 64
M.block_size = 128

local K = {
    u64("0x428A2F98D728AE22"), u64("0x7137449123EF65CD"), u64("0xB5C0FBCFEC4D3B2F"), u64("0xE9B5DBA58189DBBC"),
    u64("0x3956C25BF348B538"), u64("0x59F111F1B605D019"), u64("0x923F82A4AF194F9B"), u64("0xAB1C5ED5DA6D8118"),
    u64("0xD807AA98A3030242"), u64("0x12835B0145706FBE"), u64("0x243185BE4EE4B28C"), u64("0x550C7DC3D5FFB4E2"),
    u64("0x72BE5D74F27B896F"), u64("0x80DEB1FE3B1696B1"), u64("0x9BDC06A725C71235"), u64("0xC19BF174CF692694"),
    u64("0xE49B69C19EF14AD2"), u64("0xEFBE4786384F25E3"), u64("0x0FC19DC68B8CD5B5"), u64("0x240CA1CC77AC9C65"),
    u64("0x2DE92C6F592B0275"), u64("0x4A7484AA6EA6E483"), u64("0x5CB0A9DCBD41FBD4"), u64("0x76F988DA831153B5"),
    u64("0x983E5152EE66DFAB"), u64("0xA831C66D2DB43210"), u64("0xB00327C898FB213F"), u64("0xBF597FC7BEEF0EE4"),
    u64("0xC6E00BF33DA88FC2"), u64("0xD5A79147930AA725"), u64("0x06CA6351E003826F"), u64("0x142929670A0E6E70"),
    u64("0x27B70A8546D22FFC"), u64("0x2E1B21385C26C926"), u64("0x4D2C6DFC5AC42AED"), u64("0x53380D139D95B3DF"),
    u64("0x650A73548BAF63DE"), u64("0x766A0ABB3C77B2A8"), u64("0x81C2C92E47EDAEE6"), u64("0x92722C851482353B"),
    u64("0xA2BFE8A14CF10364"), u64("0xA81A664BBC423001"), u64("0xC24B8B70D0F89791"), u64("0xC76C51A30654BE30"),
    u64("0xD192E819D6EF5218"), u64("0xD69906245565A910"), u64("0xF40E35855771202A"), u64("0x106AA07032BBD1B8"),
    u64("0x19A4C116B8D2D0C8"), u64("0x1E376C085141AB53"), u64("0x2748774CDF8EEB99"), u64("0x34B0BCB5E19B48A8"),
    u64("0x391C0CB3C5C95A63"), u64("0x4ED8AA4AE3418ACB"), u64("0x5B9CCA4F7763E373"), u64("0x682E6FF3D6B2B8A3"),
    u64("0x748F82EE5DEFB2FC"), u64("0x78A5636F43172F60"), u64("0x84C87814A1F0AB72"), u64("0x8CC702081A6439EC"),
    u64("0x90BEFFFA23631E28"), u64("0xA4506CEBDE82BDE9"), u64("0xBEF9A3F7B2C67915"), u64("0xC67178F2E372532B"),
    u64("0xCA273ECEEA26619C"), u64("0xD186B8C721C0C207"), u64("0xEADA7DD6CDE0EB1E"), u64("0xF57D4F7FEE6ED178"),
    u64("0x06F067AA72176FBA"), u64("0x0A637DC5A2C898A6"), u64("0x113F9804BEF90DAE"), u64("0x1B710B35131C471B"),
    u64("0x28DB77F523047D84"), u64("0x32CAAB7B40C72493"), u64("0x3C9EBE0A15C9BEBC"), u64("0x431D67C49C100D4C"),
    u64("0x4CC5D4BECB3E42B6"), u64("0x597F299CFC657E2A"), u64("0x5FCB6FAB3AD6FAEC"), u64("0x6C44198C4A475817")
}

local function rotate_right(x, n)
    return (x >> n) | (x << (64-n))
end

local function CH(x, y, z)
    return (x & y) ~ ((~x) & z)
end

local function MAJ(x, y, z)
    return (x & y) ~ ( x & z) ~ (y & z)
end

local function BSIG0(x)
    return rotate_right(x, 28) ~ rotate_right(x, 34) ~ rotate_right(x, 39)
end

local function BSIG1(x)
    return rotate_right(x, 14) ~ rotate_right(x, 18) ~ rotate_right(x, 41)
end

local function SSIG0(x)
    return rotate_right(x, 1) ~ rotate_right(x, 8) ~ (x >> 7)
end

local function SSIG1(x)
    return rotate_right(x, 19) ~ rotate_right(x, 61) ~ (x >> 6)
end

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._H0 = u64(0x6A09E667F3BCC908)
    o._H1 = u64(0xBB67AE8584CAA73B)
    o._H2 = u64(0x3C6EF372FE94F82B)
    o._H3 = u64(0xA54FF53A5F1D36F1)
    o._H4 = u64(0x510E527FADE682D1)
    o._H5 = u64(0x9B05688C2B3E6C1F)
    o._H6 = u64(0x1F83D9ABFB41BD6B)
    o._H7 = u64(0x5BE0CD19137E2179)
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

    while #self._data >= 128 do
        W = {}
        for i=1,128,8 do
            local j = #W+1
            W[j] = u64(string.byte(self._data, i)) << 56
            W[j] = W[j] | u64(string.byte(self._data, i+1)) << 48
            W[j] = W[j] | u64(string.byte(self._data, i+2)) << 40
            W[j] = W[j] | u64(string.byte(self._data, i+3)) << 32
            W[j] = W[j] | u64(string.byte(self._data, i+4)) << 24
            W[j] = W[j] | u64(string.byte(self._data, i+5)) << 16
            W[j] = W[j] | u64(string.byte(self._data, i+6)) << 8
            W[j] = W[j] | u64(string.byte(self._data, i+7))
        end
        self._data = self._data:sub(129, #self._data)

        for i=17,80 do
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

        for i=1,80 do
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

    padlen = final._len % 128
    if padlen < 112 then
        padlen = 112 - padlen
    else
        padlen = 240 - padlen
    end

    len = final._len * 8
    data = string.char(1<<7) ..
        string.rep(string.char(0), padlen-1) ..
        string.char(len >> 120 & 0xFF) ..
        string.char(len >> 112 & 0xFF) ..
        string.char(len >> 104 & 0xFF) ..
        string.char(len >> 96 & 0xFF) ..
        string.char(len >> 88 & 0xFF) ..
        string.char(len >> 80 & 0xFF) ..
        string.char(len >> 72 & 0xFF) ..
        string.char(len >> 64 & 0xFF) ..
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
