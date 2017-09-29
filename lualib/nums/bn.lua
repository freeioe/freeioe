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

--- BigNum (Infinite Precision)
--
-- Design:
-- A list (table) of digits are stored with the least significant digit first.
-- Using base 10 (digits are not stored base 10) as an example, 12345 would be
-- stored in the list as 54321. A digit is a given number of bits and can be 0
-- to max value for bit size. The list of digits as a whole represent the
-- number.
--
-- The BN will digits will always be positive and a flag will be used to
-- signify if the BN is positive or negative.
--
-- The object will internally prevent excess leading (trailing in the list) 0's.
--
-- This is a integer only library and does not handle floating point. Rounding
-- strategy is truncation. Which is consistent with other GMP and Libtommath
-- but not Lua or python which use floor truncation (toward negative infinity).

local math = math

local M = {}
local M_mt = {}

-- Each digit must be 1 bit less than half the maximum size of the native
-- integer type or smaller. Smaller digits are okay as long as they are larger 
-- than 7 bits.
--
-- The 1 less than half the native size is due to many operations having
-- overflow which needs to carry to the next digit. As an example, lets use a
-- system with 32 bit integers. We end up with 15 bit digits.
--
-- If you add two 15 bit numbers together and they are the maximum size (0x7FFF)
-- you will end up with a 16 bit number. The 16th bit is the carry. It can
-- propagate through but will never cause the digit to exceed 16 bits.
--
-- Now if you multiply you get twice the number of bits. 0x7FFF * 0x7FFF will
-- result in a 30 bit digit. When we take into account the carry we get 31 bits.
-- This is why we need to have two digits fit into one native type.
--
-- Even though we have 32 bits in this example it's not possible to use that
-- extra bit due to the way the math works out. Also, we wouldn't want to use
-- it anyway. If the value is signed the high bit is used for the sign. So we'd
-- only be able to use 31 bits anyway. It's useful that the math works out that
-- we don't need to worry about signed vs unsigned underlying types.
--
-- The larger the digit bits the better performance and the larger the largest
-- possible BN. A 15 bit digit can hold less than a 25 bit digit meaning we
-- need more digits for a 25 bit number with 15 bit digits. Operations would
-- be split across multiple digits degrading performance. This is compounded
-- as the BN gets larger. Since the digits are stored in a list the maximum
-- number in the BN is capped by the number of slots possible in the list. The
-- larger the digit the larger the value that can be fit into a slot so more
-- the theoretical maximum (you'll probably run out of memory well before this)
-- BN value increases as the digit bits increase.
--
-- A note about choosing a digit size:
--
-- Lua 5.3 defaults to 64 bit integers but they are signed so a digit can be no
-- more than 30 bits. This is fine until you think about the fact that as a
-- feature Lua allows different integer types when it's compiled. Being that
-- Lua is often used in domain specific settings it's not a good idea to hard
-- code 30 bits for a digit.
--
-- Internally Lua allows numbers to be integers and floating point, long long
-- and long double in Lua 5.3. Lua handles flipping between these two as
-- needed. However, we need to be very careful none of the operations here
-- will end up being converted to floating point and possible having rounding
-- issues. Further consideration is needed because Lua can be compiled without
-- integer types and only have floating point numbers. In versions of Lua older
-- than 5.3 numbers were only floating point.
--
-- With 64 bit floating point only 52 bytes are guaranteed to always be
-- available available for the non-decimal part. We can only use 25 bit digits.
-- 52/2 = 26.  26 - 1 = 25. Now consider that Lua can also have smaller than 64
-- bit numbers. Lua older than 5.3 used 32 bit floating point numbers.
--
-- Since this library requires Lua 5.3 at a minimum and since it supports 64
-- bit integers. We're going to calculate the largest possible digit we can
-- use.
--
-- For a Lua build that uses a smaller or different native type a different
-- digit size needs to be set here. A 15 bit digit with a mask of 0x7FFF is
-- pretty safe and should work across any system.
--
-- local DIGIT_BITS = 15 -- ((2bytes * 8bits per byte) - 1)
-- local DIGIT_MASK = 0x7FFF -- ((1 << DIGIT_BITS) - 1)
--
-- Calculating DIGIT_BITS uses x > z instead of x > 0 to ensure the loop stops
-- if the number type is unsigned. This will loop forever if the underlying
-- number type is a BN but at that point this will be less than useful...
local DIGIT_BITS = 0
local x = 1
local y = 0
local z = 0
while x > z do
    z = x
    x = x << 1
    y = y + 1
end
DIGIT_BITS = ((y - 1)//2) - 1 -- Gives us 30 bits with Lua 5.3.
local DIGIT_MASK = (1 << DIGIT_BITS) - 1
local DIGIT_MAX = DIGIT_MASK
-- Carry needs to be 1 bit more than the digit because a carry will fill the
-- next bit. Carry is always 1 bit more than DIGIT_BITS. We'll need to bring
-- negative numbers back into range when dealing with subtraction.
local DIGIT_CMASK = (1 << (DIGIT_BITS + 1)) - 1
x = nil
y = nil
z = nil

-- [R]RMAP is used for converting between BN and strings. The map only supports
-- base 10 and base 16. These can be expanded out to say base 64 by adding the
-- additional digits in the base to the maps.
local RMAP = {
    ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
    ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["A"] = 10, ["B"] = 11,
    ["C"] = 12, ["D"] = 13, ["E"] = 14, ["F"] = 15
}

local RRMAP = {
    "0", "1", "2", "3", "4", "5", "6", "7",
    "8", "9", "A", "B", "C", "D", "E", "F"
}

--- Adds leading 0's.
--
-- This allows comparison and manipulation between two BNs of different sizes.
--
-- @param a The BN to expand
-- @param b Can be a number which a._digits will be expanded to. Or it can be
--          a BN. When it is a BN both a or b will be expanded to to the larger
--          of the two's number of digits.
--
-- @ see reduce
local function expand(a, b)
    local len

    -- Expand to a given number of digits.
    local function expand_num(a, num)
        while #a._digits < num do
            a._digits[#a._digits+1] = 0
        end
    end

    if type(b) == "number" then
        expand_num(a, b)
        return
    end

    -- Expand to the larger of a or b's digits.
    if #a._digits >= #b._digits then
        expand_num(b, #a._digits)
    else
        expand_num(a, #b._digits)
    end

end

--- Removes leading 0's
--
-- After certain operations the BN will have excessive 0's. They are only
-- needed when manipulating a BN. Takes "00010" and makes it "10".
--
-- @param a The BN to reduce
--
-- @see expand
local function reduce(a)
    -- Ensure the BN is never empty.
    if #a._digits == 0 then
        a._pos = true
        a._digits = { 0 }
        return
    end

    -- Check for and remove excess 0's
    for i=#a._digits,2,-1 do
        if a._digits[i] ~= 0 then
            break
        end
        table.remove(a._digits, i)
    end

    if #a._digits == 1 and a._digits[1] == 0 then
        a._pos = true
    end
end

--- Clear a BN
--
-- @param a The BN to clear
local function reset(a)
    a._digits = { 0 }
    a._pos = true
end

--- Takes an input and turns it into a BN
--
-- If the input is already a BN it will return a copy.
--
-- @param a Input.
--
-- @return BN.
local function get_input(a)
    if M.isbn(a) then
        a = a:copy()
    else
        a = M:new(a)
    end
    return a
end

--- Convince function for getting two inputs
--
-- @param a Input a.
-- @param b Input b.
--
-- @return The inputs as BN's.
local function get_inputs(a, b)
    a = get_input(a)
    b = get_input(b)
    return a, b
end

--- Determines if the result of an operation on two BN's will be positive.
--
-- @param a Input a.
-- @param b Input b.
--
-- @return true if result is positive, otherwise false indicating negative.
local function is_pos(a, b)
    if a._pos == b._pos then
        return true
    end
    return false
end

-- Left shift whole digits by the given number of digits.
--
-- @param a BN.
-- @param b Number to shift by.
--
-- @return BN.
local function lshiftd(a, b)
    a = get_input(a)

    if b == 0 then
        return a
    end
    -- Insert 0's at the beginning of the list which is the least significant
    -- digit.
    for i=1,b do
        table.insert(a._digits, 1, 0)
    end
    reduce(a)
    return a
end

-- Right shift whole digits by the given number of digits.
--
-- @param a BN.
-- @param b Number to shift by.
--
-- @return BN.
local function rshiftd(a, b)
    a = get_input(a)

    if b == 0 then
        return a
    elseif b >= #a._digits then
        return M:new()
    end
    -- Remove digits from the beginning.
    for i=1,b do
        table.remove(a._digits, 1)
    end
    reduce(a)
    return a
end

--- Unsigned addition.
--
-- @param a BN.
-- @param b BN.
--
-- @return BN.
local function add_int(a, b)
    local c = M:new()
    local u = 0

    a, b = get_inputs(a, b)
    expand(a, b)

    for i=1,#a._digits do
        -- Add the digits and the carry.
        c._digits[i] = a._digits[i] + b._digits[i] + u
        -- Calculate carry buy pulling it off the top of the digit.
        u = c._digits[i] >> DIGIT_BITS
        -- Reduce the digit to the proper size by removing the carry.
        c._digits[i] = c._digits[i] & DIGIT_MASK
    end

    -- Add the final carry if we have one.
    if u ~= 0 then
        c._digits[#c._digits+1] = u
    end

    reduce(c)
    return c
end

-- Unsigned subtraction.
--
-- Must: a >= b
--
-- @param a BN.
-- @param b BN.
--
-- @return BN.
local function sub_int(a, b)
    local c = M()
    local min
    local max
    local u = 0

    a, b = get_inputs(a, b)
    expand(a, b)

    for i=1,#a._digits do
        -- Subtract the digits and the carry.
        -- If there is a carry we've gone negative. Mask it to get a positive
        -- number with the carry bit set. All digits are unsigned values. If
        -- this was C and we were using an unsigned 32 bit integer as the digit
        -- type then it would handle wrapping internally. However, Lua doesn't
        -- have fixed size unsigned types so we need to handle wrapping.
        c._digits[i] = (a._digits[i] - b._digits[i] - u) & DIGIT_CMASK
        -- Calculate carry buy pulling it off the top of the digit.
        u = c._digits[i] >> DIGIT_BITS
        -- Reduce the digit to the proper size by removing the carry.
        c._digits[i] = c._digits[i] & DIGIT_MASK
    end

    reduce(c)
    return c
end

--- Performs a bitwise operation on two BN's.
--
-- This is a digit to digit operation. The value of digit a at index i will be
-- bitwised with digit b at index i.
--
--
-- @param a  BN.
-- @param b  BN.
-- @param op Function that performs a bitwise operation on a BN digit.
--
-- @return BN.
local function bitwise_int(a, b, op)
    local c

    a, b = get_inputs(a, b)
    expand(a, b)

    c = M:new()
    expand(c, a)
    for i=1,#a._digits do
        c._digits[i] = op(a._digits[i], b._digits[i])
    end

    reduce(c)
    return c
end

--- Division with remainder.
--
-- Standard division rules apply. Such as, cannot divide by 0.
--
-- We are not doing division by subtraction, while simple, is not used because
-- it has such poor performance anything you'd need a BN for will take an
-- obscenely long time to complete. Instead, binary long division of unsigned
-- integers is used.  Sign is handled within the function but outside of the
-- core algorithm.
--
-- @param a BN.
-- @param b BN.
--
-- @return BN, remainder.
-- @return nil, error.
local function div_remain(a, b)
    local e
    local q
    local r
    local qpos
    local rpos

    a, b = get_inputs(a, b)
    if a == M.ZERO then
        return  M:new(), M:new()
    elseif b == M.ZERO then
        return nil, "divide by 0"
    elseif b == M:new(1) then
        return a, M:new()
    end

    -- The quotient's sign is based on the sign of the dividend and divisor.
    -- Standard pos and pos = pos, neg and neg = pos, pos and neg = neg.
    qpos = is_pos(a, b)
    -- Technically the remainder can't be negative. However, it is possible
    -- to provide either a positive or a negative remainder. We'll use C99
    -- rules for the remainder where it is aways the sign of the dividend.
    rpos = a._pos
    -- Set a and b to positive because the division algorithm only works with
    -- positive numbers.
    a._pos = true
    b._pos = true

    -- loop though every bit. len_bits gives us a total and we need to loop
    -- by bit position (index) so subtract 1. E.g. (1 << 0) is the first bit.
    --
    -- Note that when we do (1 << e) the 1 needs to be converted to a BN
    -- because 1 << 86 will most likely be larger than a native number can
    -- hold.
    e = a:len_bits() - 1
    -- r is the remainder after an operation and when we drop down to the next
    -- level (long division) we will add it to the value we're pulling down.
    -- Once r is larger than the divisor it gets moved to the quotient.
    r = M:new()
    q = M:new()
    while e >= 0 do
        -- r is the remainder and it's also used for the drop down add.
        -- Shift it left one digit so it's the next field larger for the top.
        r = r << 1
        -- Check if there is a bit set at this position in the dividend.
        -- If so we set the first bit in r as the drop down and add part.
        if a & (M:new(1) << e) > 0 then
            r = r | 1
        end
        -- If r is larger than the divisor then we set r to the difference
        -- and add the difference to the quotient.
        if r >= b then
            r = r - b
            q = q | (M:new(1) << e)
        end
        e = e - 1
    end

    q._pos = qpos
    if r ~= 0 then
        r._pos = rpos
    end

    reduce(q)
    reduce(r)
    return q, r
end

local function set_string(s, n)
    local u = 0
    local r = 0
    local c = 0
    local b = 0
    local t = 0
    local base = 10

    -- Convert the number to a string and remove any decimal portion. We're
    -- using 0 truncation so it doesn't matter what's there.
    n = tostring(n)
    n = n:gsub("%.%d*", "")
    n = n:gsub("U?L?L?$", "")

    -- Nothing left so assume 0.
    if n == "" then
        return true
    end

    -- Check if the number is negative.
    if n:sub(1, 1) == "-" then
        s._pos = false
        n = n:sub(2, #n)
    end

    -- Convert to uppercase so we can have one check for the hex prefix. If
    -- it's a hex number change the base to 16 and remove the prefix.
    n = n:upper()
    if n:sub(1, 2) == "0X" then
        base = 16
        n = n:sub(3, #n)
    end

    -- Go though each digit in the string from most to least significant.
    -- We're using single digit optimizations for multiplication and division
    -- because: 1. It gives us a performance boost since base will never be
    -- a BN. 2. We can't use the BN's __mul and __add functions because those
    -- call get_input(s) which in turn call :set. Infinite loops are bad.
    --
    -- The process here is set the digit, multiply by base to move it over.
    -- Add the next and repeat until we're out of digits.
    for i=1,#n do
        -- Take the current digit and get the numeric value it corresponds to.
        c = n:sub(i, i)
        b = RMAP[c]
        if b == nil then
            reset(s)
            return false
        end

        -- Multiply by base so we can move what we already have over to the
        -- make room for adding the next digit.
        u = 0
        for i=1,#s._digits do
            s._digits[i] = (s._digits[i] * base) + u
            u = s._digits[i] >> DIGIT_BITS
            s._digits[i] = s._digits[i] & DIGIT_MASK
        end
        if u ~= 0 then
            s._digits[#s._digits+1] = u
        end

        -- Add the digit.
        s._digits[1] = s._digits[1] + b
        u = s._digits[1] >> DIGIT_BITS
        s._digits[1] = s._digits[1] & DIGIT_MASK
        -- Handle the carry from the add.
        for i=2,#s._digits do
            if u == 0 then
                break
            end
            s._digits[i] = s._digits[i] + u
            u = s._digits[i] >> DIGIT_BITS
            s._digits[i] = s._digits[i] & DIGIT_MASK
        end
        if u ~= 0 then
            s._digits[#s._digits+1] = u
        end
    end

    reduce(s)
    return true
end

local function set_number(s, n)
    n = math.floor(n)

    if n >= -DIGIT_MAX and n <= DIGIT_MAX then
        if n < 0 then
            n = -n
            s._pos = false
        end

        s._digits[1] = n
        return true
    end

    set_string(s, n)
    return true
end

--- To string internal function that will output in a given base.
--
-- Base 10 and 16 are supported.
--
-- @param a    BN.
-- @param base Base.
--
-- @return String representation of the number in the given base.
-- @return nil, error
local function tostring_int(a, base)
    local b
    local t = {}
    local t2 = {}
    local w
    local u
    local pos

    if #a._digits == 1 and a._digits[1] == 0 then
        return "0"
    end

    if base ~= 10 and base ~= 16 then
        return nil, "base not supported"
    end

    pos = a._pos
    a = a:copy()

    -- Integer division using digits. We don't want to use div_remain and BN
    -- division because that would be really slow. We can't use this method
    -- with BN's because we can only divide by amounts as large as a digit.
    -- This is fine for base because even with a 7 bit digit we an still
    -- have base be up to a 127. Really 64 is probably the largest we'd ever
    -- need in the real world.
    --
    -- This is the same div mod principal as this:
    --      local num = 1230
    --      local b = ""
    --      while num > 0 do
    --          b = tostring(num%10)..b
    --          num = num//10
    --      end
    --      print(type(b), b)
    while #a._digits > 1 or a._digits[1] ~= 0 do
        b = M:new()
        expand(b, a)
        w = 0
        -- We are going to divide by base and each division we'll get a value
        -- with one few digit in the base. We will keep replacing a with the
        -- one digit less value and keep dividing until we've gone though all
        -- digits.
        for i=#a._digits,1,-1 do
            -- Push the digit and the remainder from the last
            -- together.
            w = (w << DIGIT_BITS) | a._digits[i]
            if w >= base then
                -- If the remainder is now larger than or equal to base we need
                -- to divide the digit by the base. Then reduce the remainder
                -- down so we have the new remainder.
                u = w // base
                w = w - (u * base)
            else
                u = 0
            end
            -- Save the divided digit value.
            b._digits[i] = u
        end
        -- The remainder from this run is the numeric for the base digit in
        -- the string. Pull the digit out of the map.
        t[#t+1] = RRMAP[w+1]
        -- Update a so we can divide again to get the next digit.
        a = b
        reduce(a)
    end

    if not pos then
        t[#t+1] = "-"
    end

    -- Since the digits in the BN are in order of lest to most and the base
    -- string is most to least we need to reverse the string.
    for i=#t,1,-1 do
        t2[#t2+1] = t[i]
    end
    return table.concat(t2)
end

-- Most of the metatable operations take two inputs (a and b). One will be a BN
-- but the other might not. It could be a string, number... The input's will be
-- converted into a BN if they're not. Also, copies will be used. The input is
-- never modified in place and the result will always return an new BN.
--
-- Operations with one input are going to be a BN. We don't need to verify and
-- create a BN but instead we just copy it if we need to make modifications
-- during the operation.
M_mt.__index = M
M_mt.__add =
    -- Addition is only implemented as unsigned. We'll use addition or
    -- subtraction as needed based on certain satiations. The proper sign will
    -- be set based on these condition.
    function(a, b)
        local c
        local apos
        local bpos

        a, b = get_inputs(a, b)

        apos = a._pos
        bpos = b._pos
        a._pos = true
        b._pos = true

        if apos == bpos then
            c = add_int(a, b)
            c._pos = apos
        elseif a < b then
            c = sub_int(b, a)
            c._pos = bpos
        else
            c = sub_int(a, b)
            c._pos = apos
        end

        return c
    end
M_mt.__sub =
    -- Subtraction is only implemented as unsigned. We'll use addition or
    -- subtraction as needed based on certain satiations. The proper sign will
    -- be set based on these condition.
    function(a, b)
        local c
        local apos
        local bpos

        a, b = get_inputs(a, b)

        apos = a._pos
        bpos = b._pos
        a._pos = true
        b._pos = true

        if apos ~= bpos then
            c = add_int(a, b)
            c._pos = apos
        elseif a >= b then
            c = sub_int(a, b)
            c._pos = apos
        else
            c = sub_int(b, a)
            c._pos = not apos
        end

        return c
    end
M_mt.__mul =
    -- Base line multiplication like taught in grade school. Multiply across,
    -- then drop down and multiply the next digit. Add up all the columns to
    -- get the result.
    function(a, b)
        local c
        local r
        local u

        a, b = get_inputs(a, b)

        c = M:new()
        c._pos = is_pos(a, b)

        -- Multiplication should only have a + b digits plus 1
        -- for the carry.
        expand(c, #a._digits + #b._digits + 1)

        for i=1,#a._digits do
            u = 0

            for y=1,#b._digits do
                -- Digits in the given position from a and b that are
                -- multiplied. Add the carry, and add what was already in the
                -- digit. Instead of having a list for each time we add a
                -- product row we just update the final result row.
                r = c._digits[i+y-1] + (a._digits[i] * b._digits[y]) + u
                -- Calculate the carry.
                u = r >> DIGIT_BITS
                -- Remove the carry (if there was one) from the digit.
                c._digits[i+y-1] = r & DIGIT_MASK
            end

            -- Set the carry as the next digit in the product.
            c._digits[i+#b._digits] = u
        end
        
        reduce(c)
        return c
    end
M_mt.__div =
    -- This is an integer library so division will work the same as integer
    -- division.
    function(a, b)
        return a // b
    end
M_mt.__mod =
    -- Modulus (not to be confused with C's modulus which is just the
    -- remainder). When a and b are the same sign modulus and remainder will
    -- produce the same result.
    --
    -- Keep in mind the % operator in C is really a remainder operator! C
    -- ignores the sign and applies it after the unsigned division and
    -- remainder takes place.
    --
    -- Mathematical modulus will use the sign of a and be to determine which
    -- direction the modulus should wrap. Toward positive or toward negative.
    --
    -- For example:
    --  240 %  9 =  6
    --  240 % -9 = -3
    -- -240 %  9 =  3
    -- -240 % -9 = -6
    --
    --  240 R  9 =  6
    --  240 R -9 =  6
    -- -240 R  9 = -6
    -- -240 R -9 = -6
    function(a, b)
        local c
        a, b = get_inputs(a, b)
        _, c = div_remain(a, b)
        -- Change the wrapping direction appropriately.
        if c ~= M.ZERO and c._pos ~= b._pos then
            c = b + c
        end
        return c
    end
M_mt.__pow =
    -- Right to left binary exponentiation. This is a multiply and or square
    -- method. It reduces the number of operations significantly vs multiplying
    -- a by itself b number of times.
    --
    -- The point is to reduce the total number of multiplications a^10 we would
    -- have 10 operations if we were to multiply only.  This method we go from
    -- right to left though every bit in b. When the fist bit is odd multiply
    -- the result by the current squared amount. For every bit we square.
    --
    -- 4^10
    -- a = 4
    -- b = 10 = 0b1010
    -- c = 1
    --   0b1010 - 0 is even
    --   a = a * a -- 4 * 4 = 16
    --   go to the next bit (right shift)
    --   0b101 - 1 is odd c = c * a -- 1 * 16 = 16
    --   a = a * a -- 16 * 16 = 256
    --   go to the next bit (right shift)
    --   0b10 - 0 is even
    --   a = a * a -- 256 * 256 = 65536
    --   go to the next bit (right shift)
    --   0b1 - 1 is odd c = c * a -- 16 * 65536 = 1048576
    --   a = a * a -- 256 * 256 = 65536
    --   go to the next bit (right shift)
    --   out of bits
    --   result is c = 1048576
    --
    -- There were 3 square operations and 2 odd multiplications giving us 5
    -- total multiplications. Half of multiplying 4 ten times. There were
    -- really 4 square operations but that could have been optimized out when
    -- we knew we were on the last bit.
    function(a, b)
        local c
        local d

        a, b = get_inputs(a, b)

        -- A negative exponent will always be smaller than 0 and since we're
        -- doing integer only with truncation the result will always be 0.
        if b < M.ZERO then
            return M:new()
        end

        c = M:new(1)
        d = M:new(1)

        -- Go though each bit in b. 
        while b > 0 do
            -- If b is currently odd we multiply c with a. 
            if b & 1 == d then
                c = c * a
            end
            -- Shift be so we can check the next bit.
            b = b >> 1
            -- Square a.
            a = a * a
        end

        return c
    end
M_mt.__unm =
    function(a, b)
        a = get_input(a)
        a._pos = not a._pos
        return a
    end
M_mt.__idiv =
    function(a, b)
        local c
        a, b = get_inputs(a, b)
        c, _ = div_remain(a, b)
        return c
    end
-- Bitwise functions will set the appropriate digit bitwise function and call
-- the internal bitwise function that will go though all digits. This is a
-- digit by digit operation.
--
-- For example: 1234 & 0011 will result in
-- 1 & 0
-- 2 & 0
-- 3 & 1
-- 4 & 1
--
-- Replace & with any bitwise operation.
--
-- The BNs are compared as if they were positive. Other libraries, such as
-- Tommath don't have special handling for negative numbers. Tommath ignores
-- the negative and the result uses the sign of the second number but only
-- because it simplifies the code. It does not appear to be a concious design
-- decision.
M_mt.__band =
    function(a, b)
        local function op(a, b)
            return a & b
        end
        return bitwise_int(a, b, op)
    end
M_mt.__bor =
    function(a, b)
        local function op(a, b)
            return a | b
        end
        return bitwise_int(a, b, op)
    end
M_mt.__bxor =
    function(a, b)
        local function op(a, b)
            return a ~ b
        end
        return bitwise_int(a, b, op)
    end
M_mt.__bnot =
    -- Not the unary ~ operator. Lua uses ~ in front of a value for unary and ~
    -- between values for xor. This is ~ before, the unary operator. Flips all
    -- bits in the value.
    function(a)
        a = get_input(a)
        return -(a+1)
    end
M_mt.__shl =
    -- Left shift. b is always treated as a number. This does not support
    -- shifting by a BN amount.
    function(a, b)
        local c
        local u
        local t
        local uu
        local mask
        local shift

        a, b = get_inputs(a, b)
        if not b._pos then
            return nil, "Cannot shift by negative"
        end
        t = b
        b = b:asnumber()
        if M:new(b) ~= t then
            return nil, "Overflow"
        end

        -- Determine how many digits we could shift by and shift by that many
        -- digits.
        c = b // DIGIT_BITS 
        a = lshiftd(a, c)

        -- Determine how many bits remain that have not been shifted during the
        -- digit shift.
        c = b % DIGIT_BITS
        if c == 0 then
            return a
        end

        -- Generate a mask and how much we need to shift by.
        mask = (1 << c) - 1
        shift = DIGIT_BITS - c

        u = 0
        for i=1,#a._digits do
            -- Shift, and mask it down to the carry.
            uu = (a._digits[i] >> shift) & mask
            -- Shift and add the carry from the last operation.
            a._digits[i] = ((a._digits[i] << c) | u) & DIGIT_MASK
            -- Update our carry.
            u = uu
        end

        -- If a carry is left put it into a new digit.
        if u ~= 0 then
            a._digits[#a._digits+1] = u
        end

        reduce(a)
        return a
    end
M_mt.__shr =
    -- Right shift. b is always treated as a number. This does not support
    -- shifting by a BN amount.
    function(a, b)
        local c
        local u
        local t
        local uu
        local mask
        local shift

        a, b = get_inputs(a, b)
        if not b._pos then
            return nil, "Cannot shift by negative"
        end
        t = b
        b = b:asnumber()
        if M:new(b) ~= t then
            return nil, "Overflow"
        end

        -- Determine how many digits we could shift by and shift by that many
        -- digits.
        c = b // DIGIT_BITS 
        a = rshiftd(a, c)

        -- Determine how many bits remain that have not been shifted during the
        -- digit shift.
        c = b % DIGIT_BITS
        if c == 0 then
            return a
        end

        -- Generate a mask and how much we need to shift by.
        mask = (1 << c) - 1
        shift = DIGIT_BITS - c

        u = 0
        for i=#a._digits,1,-1 do
            -- Mask off the amount we're shifting by.
            uu = a._digits[i] & mask
            -- Move the value to the right since it's a right shift and add the
            -- carry onto the most significant side. The carry was the least
            -- significant side from the previous digit and the right of that
            -- is the most significant of the next digit.
            a._digits[i] = (a._digits[i] >> c) | (u << shift)
            -- Update our carry.
            u = uu
        end

        reduce(a)
        return a
    end
M_mt.__concat =
    function(a, b)
        -- Turn the values if they're BNs into strings and let Lua handle if
        -- conversion for other types.
        if M.isbn(a) then
            a = tostring(a)
        end
        if M.isbn(b) then
            b = tostring(b)
        end
        return a..b
    end
M_mt.__len =
    -- Length is the number of bytes in the BN. There may be many more bytes
    -- than are actually used due to the digit size. For example if a digit is
    -- 128 bit and the BN has the number 2 in it then it will have a length of
    -- 16 bytes. This will be rounded up to always equal 1 byte even if there
    -- are less digits. For example, 1, 15 byte digit will return 2 bytes used.
    -- 120, 15 byte digits is exactly 8 bytes so no rounding up is necessary.
    function(a)
        local b

        b = #a._digits * DIGIT_BITS
        b = b + (8 - (b % 8))
        return b // 8
    end
M_mt.__eq =
    function(a, b)
        a, b = get_inputs(a, b)
        if a._pos ~= b._pos or #a._digits ~= #b._digits then
            return false
        end

        for i=#a._digits,1,-1 do
            if a._digits[i] ~= b._digits[i] then
                return false
            end
        end

        return true
    end
M_mt.__lt =
    function(a, b)
        local x

        a, b = get_inputs(a, b)
        if (not a._pos and b._pos) or #a._digits < #b._digits then
            return true
        elseif (a._pos and not b._pos) or #a._digits > #b._digits then
            return false
        end

        if not a._pos then
            x = a
            a = b
            b = x
        end

        for i=#a._digits,1,-1 do
            if a._digits[i] < b._digits[i] then
                return true
            elseif a._digits[i] > b._digits[i] then
                return false
            end
        end

        return false
    end
M_mt.__le =
    function(a, b)
        a, b = get_inputs(a, b)
        if a < b or a == b then
            return true
        end
        return false
    end
M_mt.__tostring = 
    -- Default string conversion is base 10 because that's what the internal
    -- one does.
    function(a)
        return tostring_int(a, 10)
    end

-- Object

--- Create a new BN.
--
-- @param Optional starting value. If not set the BN will be equal
-- to zero.
--
-- @return BN.
function M:new(n)
    local o

    if self ~= M then
        return nil, "first argument must be self"
    end

    if n ~= nil and M.isbn(n) then
        return n:copy()
    end

    o = setmetatable({}, M_mt)
    -- The BN is made of 2 parts. The sign and a list of digits.
    o._pos = true
    o._digits = { 0 }
    if n ~= nil then
        o:set(n)
    end

    return o
end
setmetatable(M, { __call = M.new })

--- Duplicate a BN.
--
-- @return BN.
function M:copy()
    local n

    n = M:new()
    n._pos = self._pos
    n._digits = {}

    for i=1,#self._digits do
        n._digits[i] = self._digits[i]
    end

    return n
end

--- Absolute value.
--
-- @return BN.
function M:abs()
    local a

    a = get_input(self)
    a._pos = true
    return a
end

--- Remainder of a division operation.
--
-- This is not mathematical modulus but a true remainder. The sign is
-- determined using C99 rules.
--
-- @param b Amount to divide by to determine the remainder.
--
-- @return BN.
function M:remain(b)
    local a
    local c
    a, b = get_inputs(self, b)
    _, c = div_remain(a, b)
    return c
end

--- The number of bits used by the number in the BN.
--
-- This is based on the number in the BN not the number of digits in the BN
-- digit list.
--
-- For example, "123456789012345678901234567" is 87 bits.
--
-- @return Number of bits as a native number.
function M:len_bits()
    local b
    local c = 0

    if self == M.ZERO then
        return 1
    end

    b = #self._digits * DIGIT_BITS
    -- Only the last digit can have less than the full number
    -- of bits set.
    while c <= DIGIT_BITS-1 and (self._digits[#self._digits] & (1 << (DIGIT_BITS - c))) == 0 do
        c = c + 1
        b = b - 1
    end

    return b+1
end

--- The number of bytes the number in the BN is using.
--
-- Unlike length which is the number of bytes allocated this is like num_bits
-- which only accounts for what's used in the BN.
-- 
-- For example, with a 15 bit digit:
-- BN = 255: 1 byte used but #self = 2
-- BN = 256: 2 byte used and #self = 2
--
-- @return Number of bytes as a native number.
function M:len_bytes()
    local bits

    bits = self:len_bits()
    if bits <= 8 then
        return 1
    end

    if bits % 8 ~= 0 then
        bits = bits + (8 - (bits % 8))
    end
    return bits // 8
end

--- The number of digits in the number in the given base.
--
-- Supported bases:
-- * 10
-- * 16
--
-- @param base The base to consider.
--
-- @return BN.
function M:len_digits(base)
    local a
    if not base then
        base = 10
    end
    return #tostring_int(self, base)
end

--- Set the value of a BN to the given value.
--
-- The value can be a number or a string.
-- String bases supported:
-- * 10
-- * 16 (must star with 0x or 0X)
--
-- @param n Number.
--
-- @return BN.
function M:set(n)
    reset(self)

    -- Nothing to set so assume 0.
    if n == nil then
        return true
    end

    -- If it's a bn we just copy it.
    if M.isbn(n) then
        self = n:copy()
        return true
    end

    if type(n) == "number" then
        return set_number(self, n)
    end

    return set_string(self, n)
end

--- Output the BN as a hex string.
--
-- Hex prefix 0x/0X will not be prepended.
--
-- @return String of hex digits representing the BN.
function M:ashex()
    return tostring_int(self, 16)
end

--- Output the BN as a native number.
--
-- If the BN is larger than the native type then as much as can be fit into
-- the native type will be. The most significant digits will be truncated.
--
-- @return A native number.
function M:asnumber()
    local bytes
    local q = 1
    local x = 0

    -- The size of a native number can be variable.
    -- We need to determine the number of bits in
    -- it so we can determine how many digits from
    -- the BN we can fit into the native number.
    while q > 0 do
        x = x+1
        q = 1 << x
    end
    x = x - 1

    x = math.min(#self._digits, ((x+DIGIT_BITS-1)//DIGIT_BITS)-1)

    q = self._digits[x]
    for i=x-1,1,-1 do
        q = (q << DIGIT_BITS) | self._digits[i]
    end
    if not self._pos then
        q = q * -1
    end

    return q
end

--- Output the BN as an array of bytes with most significant digit first.
--
-- @return An array of bytes.
--
-- @see asbytestring
function M:asbytearray()
    local t = {}

    for i=self:len_bytes()-1,0,-1 do
        t[#t+1] = ((self >> (i*8)) & 0xFF):asnumber()
    end
    return t
end

--- Output the BN as an array of bytes in a string.
--
-- @return A byte string.
--
-- @see asbytearray
function M:asbytestring()
    local b

    b = self:asbytearray()
    for i=1,#b do
        b[i] = string.char(b[i])
    end
    return table.concat(b)
end

-- Static

--- 0 constant used for equality checks.
--
-- == only works when two tables have the same __eq meta function. Thus
-- a == 0 cannot be used. Instead a == M.ZERO is necessary.
M.ZERO = M:new()

--- Check if the object a BN.
--
-- @param t Table to check.
--
-- @return true if it is a BN, otherwise false.
function M.isbn(t)
    if type(t) == "table" and getmetatable(t) == M_mt then
        return true
    end
    return false
end

return M
