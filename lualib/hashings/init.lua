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

local M = {}

M.adler32 = require("hashings.adler32")
M.blake2b = require("hashings.blake2b")
M.blake2s = require("hashings.blake2s")
M.crc32 = require("hashings.crc32")
M.md5 = require("hashings.md5")
M.ripemd160 = require("hashings.ripemd160")
M.sha1 = require("hashings.sha1")
M.sha256 = require("hashings.sha256")
M.sha3_256 = require("hashings.sha3_256")
M.sha3_512 = require("hashings.sha3_512")
M.sha512 = require("hashings.sha512")
M.whirlpool = require("hashings.whirlpool")

M.hmac = require("hashings.hmac")
M.pbkdf2 = require("hashings.pbkdf2")

M.algorithms = { 
    "adler32",
    "blake2b",
    "blake2s",
    "crc32",
    "md5",
    "ripemd160",
    "sha1",
    "sha256",
    "sha3_256",
    "sha3_512",
    "sha512",
    "whirlpool"
}

local alg_map = {
    adler32 = M.adler32,
    blake2b = M.blake2b,
    blake2s = M.blake2s,
    crc32 = M.crc32,
    md5 = M.md5,
    ripemd160 = M.ripemd160,
    sha1 = M.sha1,
    sha256 = M.sha256,
    sha3_256 = M.sha3_256,
    sha3_512 = M.sha3_512,
    sha512 = M.sha512,
    whirlpool = M.whirlpool
}

function M:new(alg, data)
    local a

    a = alg_map[alg]
    if a == nil then
        return nil
    end
    return a:new(data)
end
setmetatable(M, { __call = M.new })

return M
