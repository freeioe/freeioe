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

local MOD = 65521

M.digest_size = 8
M.block_size = 8

function M:new(data)
    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    o._b1 = u32(1)
    o._b2 = u32(0)

    if data ~= nil then
        o:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = M:new()
    o._b1 = self._b1:copy()
    o._b2 = self._b2:copy()
    return o
end

function M:update(data)
    local b

    if data == nil then
        data = ""
    end

    data = tostring(data)

    for i=1,#data do
        b = string.byte(data, i)
        self._b1 = (self._b1+b) % MOD
        self._b2 = (self._b2+self._b1) % MOD
    end
end

function M:digest()
    return ((self._b2 << 16) | self._b1):asbytestring()
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
