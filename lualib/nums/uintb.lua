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

--- Fixed width unsigned integers backed by Lua's number type.

local bn = require("nums.bn")

local M = {}
local M_mt = {}

-- Private

--- Get the input in a workable form.
--
-- The order of input will not necessarily reflect the output. A swapped flag
-- will be returned to indicate that a, b are being returned b, a. The input
-- input is normalized into uint, BN as the return values.
--
-- The unit returned is a new object and intended to be returned by the caller.
--
-- @param a Input.
-- @param b Input.
--
-- @return unit, BN, swapped.
local function get_inputs(a, b)
    local t
    local v
    local s = false

    if M.isuint(a) then
        t = a
        v = b
    else
        t = b
        v = a
        s = true
    end

    v = bn(v)
    return t:copy(), v, s
end

local function reduce_range(o)
    if o._bn == o._max then
        o._bn:set(0)
    elseif o._bn < 0 or o._bn > o._max then
        o._bn = o._bn % o._max
    end
end

-- M_mt

M_mt.__index = M
M_mt.__add =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b + a._bn
        else
            a._bn = a._bn + b
        end

        reduce_range(a)
        return a
    end
M_mt.__sub =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b - a._bn
        else
            a._bn = a._bn - b
        end

        reduce_range(a)
        return a
    end
M_mt.__mul =
    function(a, b)
        a, b = get_inputs(a, b)

        a._bn = a._bn * b

        reduce_range(a)
        return a
    end
M_mt.__div =
    function(a, b)
        return a // b
    end
M_mt.__mod =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b % a._bn
        else
            a._bn = a._bn % b
        end

        reduce_range(a)
        return a
    end
M_mt.__pow =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b ^ a._bn
        else
            a._bn = a._bn ^ b
        end

        reduce_range(a)
        return a
    end
M_mt.__unm =
    function(a)
        a = a:copy()

        a._bn = -a._bn

        reduce_range(a)
        return a
    end
M_mt.__idiv =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)
        if s and b == 0 then
            a._val = 0
            return a
        end
        -- if b == 0 then divide by 0 exception, let it happen.

        if s then
            a._bn = b // a._bn
        else
            a._bn = a._bn // b
        end

        reduce_range(a)
        return a
    end
M_mt.__band =
    function(a, b)
        a, b, s = get_inputs(a, b)

        a._bn = a._bn & b

        reduce_range(a)
        return a
    end
M_mt.__bor =
    function(a, b)
        a, b, s = get_inputs(a, b)

        a._bn = a._bn | b

        reduce_range(a)
        return a
    end
M_mt.__bxor =
    function(a, b)
        a, b = get_inputs(a, b)

        a._bn = a._bn ~ b

        reduce_range(a)
        return a
    end
M_mt.__bnot =
    function(a)
        a = a:copy()

        a._bn = ~a._bn

        reduce_range(a)
        return a
    end
M_mt.__shl =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b << a._bn
        else
            a._bn = a._bn << b
        end

        reduce_range(a)
        return a
    end
M_mt.__shr =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)

        if s then
            a._bn = b >> a._bn 
        else
            a._bn = a._bn >> b
        end

        reduce_range(a)
        return a
    end
M_mt.__concat =
    function(a, b)
        if M.isuint(a) and M.isuint(b) then
            return a._bn..b._bn
        elseif M.isuint(a) and not M.isuint(b) then
            return a._bn..b
        end
        return a..b._bn
    end
M_mt.__len =
    function(a)
        return a._bits
    end
M_mt.__eq =
    function(a, b)
        a, b = get_inputs(a, b)
        return a._bn == b
    end
M_mt.__lt =
    function(a, b)
        local s

        a, b, s = get_inputs(a, b)
        if s then
            return a._bn > b
        end
        return a._bn < b
    end
M_mt.__le =
    function(a, b)
        if a < b or a == b then
            return true
        end
        return false
    end
M_mt.__tostring = 
    function(a)
        return tostring(a._bn)
    end

-- Object

function M:new(bits, n)
    local o = setmetatable({}, M_mt)

    if self ~= M then
        return nil, "first argument must be self"
    end

    if bits == nil then
        return nil, "bits required"
    end

    if M.isuint(bits) then
        o._bits = bits._bits
        o._max = bits._max
        if n ~= nil then
            o._bn = bn(n)
        else
            o._bn = bn(bits._bn)
        end
    else
        o._bits = bits
        o._max = bn(1) << o._bits
        if n ~= nil then
            o._bn = bn(n)
        else
            o._bn = bn()
        end
    end

    reduce_range(o)
    return o
end

-- Static

function M.isuint(t)
    if type(t) == "table" and getmetatable(t) == M_mt then
        return true
    end
    return false
end

function M.u8(n)
    return M:new(8, n)
end

function M.u16(n)
    return M:new(16, n)
end

function M.u32(n)
    return M:new(32, n)
end

function M.u64(n)
    return M:new(64, n)
end

function M.u128(n)
    return M:new(128, n)
end

function M.u256(n)
    return M:new(256, n)
end

function M.u512(n)
    return M:new(512, n)
end

-- M

function M:copy()
    return M:new(self._bits, self._bn)
end

function M:set(n)
    if M.isuint(n) then
        self._bn = n._val
    else
        self._bn:set(n)
    end
    reduce_range(self)
end

function M:swape()
    local v = {}
    local n = bn()
    local t

    v = self:asbytearray()
    for i=1,#v//2 do
        t = v[i]
        v[i] = v[#v-i+1]
        v[#v-i+1] = t
    end

    t = {}
    for i=#v,1,-1 do
        t[#t+1] = v[i]
    end

    for i=1,#t do
        n = n | (bn(t[i]) << i*8-8)
    end

    return M:new(self._bits, n)
end

function M:asnumber()
    return self._bn:asnumber()
end

function M:asbn()
    return self._bn:copy()
end

function M:ashex(width)
    local s

    s = self._bn:ashex()

    if width == nil or #s >= width then
        return s
    end

    return string.rep("0", width-#s)..s
end

function M:asbytearray()
    local c

    c = self._bn:asbytearray()
    -- Fixed size type so we need fixed size output
    for i=1,(self._bits//8)-#c do
        table.insert(c, 1, 0)
    end

    return c
end

function M:asbytestring()
    local b

    b = self:asbytearray()
    for i=1,#b do
        b[i] = string.char(b[i])
    end
    return table.concat(b)
end

return M
