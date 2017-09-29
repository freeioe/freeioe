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
local hmac = require("hashings.hmac")

local M = {}

local function sxor(s1, s2)
    local b1 = {}
    local b2 = {}
    local b3 = {}

    for i=1,#s1 do
        b1[#b1+1] = string.byte(s1, i)
    end
    for i=1,#s2 do
        b2[#b2+1] = string.byte(s2, i)
    end
    for i=1,#b1 do
        b3[#b3+1] = string.char(b1[i] ~ b2[i])
    end

    return table.concat(b3)
end

local function hexify(h)
    local out = {}

    for i=1,#h do
        out[i] = string.format("%02X", string.byte(h, i))
    end
    return table.concat(out)
end

function M:pbkdf2(hm, pass, salt, it)
    local u
    local t

    u = hmac(hm, pass, salt..u32(1):asbytestring()):digest()
    t = u
    for i=2,it do
        u = hmac(hm, pass, u):digest()
        t = sxor(t, u)
    end

    return hexify(t)
end
setmetatable(M, { __call = M.pbkdf2 })

return M
