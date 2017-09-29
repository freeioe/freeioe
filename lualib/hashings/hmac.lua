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

local M = {}
local M_mt = { __metatable = {}, __index = M }

function M:new(hm, key, data)
    local th
    local tk = {}
    local ipad = {}

    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)
    o._hm = hm

    -- Compute the key.
    if #key > hm.block_size then
        th = hm(key)
        key = th:digest()
    end
    for i=1,#key do
        tk[#tk+1] = string.byte(key, i)
    end
    for i=#key+1,hm.block_size do
        tk[#tk+1] = 0
    end

    -- Generate the inner and outer padding.
    o._opad = {}
    for i=1,#tk do
        ipad[i] = string.char(tk[i] ~ 0x36)
        o._opad[i] = string.char(tk[i] ~ 0x5C)
    end
    ipad = table.concat(ipad)
    o._opad = table.concat(o._opad)

    -- Start the hash witht the inner padding
    o._hash = o._hm(ipad)

    if data ~= nil then
        o._hash:update(data)
    end

    return o
end
setmetatable(M, { __call = M.new })

function M:copy()
    local o = setmetatable({}, M_mt)
    o._hm = self._hm
    o._hash = self._hash:copy()
    o._opad = self._opad
    return o
end

function M:update(data)
    self._hash:update(data)
end

function M:digest()
    local final
    local digest
    local th

    final = self:copy()
    digest = final._hash:digest()
    th = final._hm(final._opad)
    th:update(digest)

    return th:digest()
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
