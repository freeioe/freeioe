--[[lit-meta
    name = "lil-evil/toml"
    version = "0.1.0"
    dependencies = {}
    description = "A toml v1.0.0 encoder and decoder"
    tags = { "toml", "parser" }
    license = "MIT"
    author = { name = "lilevil", email = "/" }
    homepage = "https://github.com/lil-evil/toml.lua"
  ]]

--[[
MIT License

Copyright (c) 2023 lil-evil

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]




-- ========== errors ==========
local error_code = {
  expected_header_close_bracket = "EXP_HEAD_BRACKET",
  expected_array_header_close_bracket = "EXP_ARR_HEAD_BRACKET",
  expected_comment_or_ws = "EXP_COM_OR_WS",
  expected_dot = "EXP_DOT",

  invalid_bare_key_ws = "INV_BK_WS",
  invalid_bare_key_char = "INV_BK_CHAR",
  invalid_string_term = "INV_STR_TERM",
  invalid_escape_char = "INV_ESC_SEQ",
  invalid_escape_utf8 = "INV_ESC_UTF8",
  invalid_number = "INV_NUMB",
  invalid_number_exp = "INV_NUMB_EXP",
  invalid_number_oct = "INV_NUMB_OCT",
  invalid_number_bin = "INV_NUMB_BIN",
  invalid_number_hex = "INV_NUMB_HEX",
  invalid_value = "INV_VALUE",
  invalid_inline_term = "INV_TBL_INL_TERM",
  invalid_local_date = "INV_LDATE",
  invalid_date = "INV_DATE",
  invalid_date_offset = "INV_DATE_OFFSET",
  invalid_date_sec = "INV_DATE_SEC",
  invalid_date_min = "INV_DATE_MIN",
  invalid_date_hour = "INV_DATE_HOUR",
  invalid_date_day = "INV_DATE_DAY",
  invalid_date_month = "INV_DATE_MONTH",
  invalid_unicode_char = "INV_UNICODE_CHAR",

  redefine = "REDEF",
  redefine_inline = "REDEF_INLINE",
  no_value = "NO_VALUE",
  missing_value = "MISSING_VALUE",
}

local error_message = {
  [error_code.expected_header_close_bracket] = "Invalid header at line %s: expected close bracket",
  [error_code.expected_array_header_close_bracket] =
  "Invalid array header at line %s, pos %s: expected double close bracket",
  [error_code.expected_comment_or_ws] = "Expected comment or white space until end of the line %s, pos %s",
  [error_code.expected_dot] = "Expected . to start new key at line %s, pos %s",

  [error_code.invalid_bare_key_ws] = "Invalid bare-key at line %s, pos %s: unexpected white space",
  [error_code.invalid_bare_key_char] = "Invalid bare-key at line %s, pos %s: unexpected character",
  [error_code.invalid_string_term] = "Unterminated string at line %s, pos %s",
  [error_code.invalid_escape_char] = "Invalid escape character at line %s, pos %s",
  [error_code.invalid_escape_utf8] = "Invalid unicode sequence at line %s, pos %s",
  [error_code.invalid_number] = "Invalid number at line %s, pos %s",
  [error_code.invalid_number_exp] = "Invalid number exponent at line %s, pos %s",
  [error_code.invalid_number_oct] = "Invalid octal number at line %s, pos %s",
  [error_code.invalid_number_bin] = "Invalid binary number at line %s, pos %s",
  [error_code.invalid_number_hex] = "Invalid hexadecimal number at line %s, pos %s",
  [error_code.invalid_value] = "Unknown value at line %s, pos %s",
  [error_code.invalid_inline_term] = "Unterminated inline table at line %s, pos %s",
  [error_code.invalid_local_date] = "Invalid local date at line %s, pos %s",
  [error_code.invalid_date] = "Invalid rfc3339 date at line %s, pos %s",
  [error_code.invalid_date_offset] = "Invalid rfc3339 date offset at line %s, pos %s",
  [error_code.invalid_date_sec] = "Invalid date at line %s, pos %s: invalid number of seconds",
  [error_code.invalid_date_min] = "Invalid date at line %s, pos %s: invalid number of minutes",
  [error_code.invalid_date_hour] = "Invalid date at line %s, pos %s: invalid number of hours",
  [error_code.invalid_date_day] = "Invalid date at line %s, pos %s: invalid number of days",
  [error_code.invalid_date_month] = "Invalid date at line %s, pos %s: invalid number of months",
  [error_code.invalid_unicode_char] = "Invalid utf-8 char at line %s, pos %s",

  [error_code.redefine] = "Can't redefine existing key at line %s, pos %s",
  [error_code.redefine_inline] = "Can't add or redefine key inside of an inline table at line %s, pos %s",
  [error_code.no_value] = "Invalid key-value pair at line %s, pos %s",
  [error_code.missing_value] = "No value provided at line %s, pos %s"
}


-- ========== utilities ==========
local stringchar, stringbyte, stringmatch, stringsub, stringgsub, stringfind = string.char, string.byte, string.match,
    string.sub, string.gsub, string.find
local mathinf, mathnan = math.huge, math.abs(0/0)
local TAB, SPACE, LF, CR = stringchar(0x09), stringchar(0x20), stringchar(0x0a), stringchar(0x0d)


local function stringtrim(str)
  return str:gsub("^%s*(.-)%s*$", "%1")
end

local function is_table_empty(tbl)
  local empty = true
  for k, v in pairs(tbl) do
    local v_meta = getmetatable(v)
    if type(v) ~= "table" or v and (v.__tomlinline or (v_meta.__tomlheader and v_meta.__tomltype ~= "array")) then
      empty = false
      break
    end
  end
  return empty
end


local pattern_barkey, pattern_quote = "[%w%-_]", "[\"']"

local escape = {
  b = "\b",
  t = "\t",
  n = "\n",
  f = "\f",
  r = "\r",
  ['"'] = '"',
  ["'"] = "'",
  ["\\"] = "\\",
}

local pattern_date = "^(%d%d%d%d%-%d%d%-%d%d)([Tt%s])(%d%d:%d%d:%d%d%.?%d*)([Zz%-%+]?)(%d?%d?:?%d?%d?)$"
local pattern_ldate = "^%d%d%d%d%-%d%d%-%d%d$"
local pattern_ltime = "^%d%d:%d%d:%d%d%.?%d*$"

local match_date = "^(%d%d%d%d)-(%d%d)-(%d%d)$"
local match_time = "^(%d%d):(%d%d):(%d%d)(.?%d*)$"
local match_offset = "(%d%d):(%d%d)"

local date_meta = {
  __index = function(t, k)
    if k == "ms" then
      return stringmatch(tostring(t.timestamp / 1000), "%.(.-)$") or "0"
    end

    local f = {
      year = "%Y",
      month = "%m",
      day = "%d",
      hour = "%H",
      min = "%M",
      sec = "%S"
    }
    return f[k] and os.date(f[k], t.timestamp / 1000)
  end
}

local function validate_date(tbl, parser)
  --{ year, month, day, hour, min, sec }

  if (tbl.sec < 0 or tbl.sec > 60) then
    parser:error(error_code.invalid_date_sec)
  elseif (tbl.min < 0 or tbl.min > 59) then
    parser:error(error_code.invalid_date_min)
  elseif (tbl.hour < 0 or tbl.hour > 23) then
    parser:error(error_code.invalid_date_hour)
  elseif (tbl.month < 1 or tbl.month > 12) then
    parser:error(error_code.invalid_date_month)
  end

  local is_leap_year = (tbl.year % 4) == 0
  if (tbl.year % 100) == 0 and (tbl.year % 400) ~= 0 then
    is_leap_year = false
  end

  local days = { 31, is_leap_year and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

  if tbl.day < 1 or tbl.day > days[tbl.month] then
    parser:error(error_code.invalid_date_day)
  end
end

-- https://stackoverflow.com/a/26071044
local function utf8(decimal, parser)
  --https://unicode.org/glossary/#unicode_scalar_value
  if (decimal < 0 or decimal > 0xd7ff) and (decimal < 0xe000 or decimal > 0x10ffff ) then
    parser:error(error_code.invalid_escape_utf8)
  end
  local bytemarkers = { {0x7FF,192}, {0xFFFF,224}, {0x1FFFFF,240} }
    if decimal<128 then return string.char(decimal) end
    local charbytes = {}
    for bytes,vals in ipairs(bytemarkers) do
      if decimal<=vals[1] then
        for b=bytes+1,2,-1 do
          local mod = decimal%64
          decimal = (decimal-mod)/64
          charbytes[b] = string.char(128+mod)
        end
        charbytes[1] = string.char(vals[2]+decimal)
        break
      end
    end
    return table.concat(charbytes)
end

-- https://toml.io/en/v1.0.0#string
local function validate_unicode(char, parser)
  local byte = stringbyte(char)

  if (byte <= 0x8) or (byte >= 0xa and byte <= 0x1f) or byte == 0x7f then
    parser:error(error_code.invalid_unicode_char)
  end

  return char
end




local function create_table(t, inline, header)
  return setmetatable(t or {},
    { __tomltype = "table", __jsontype = "object", __tomlinline = inline or false, __tomlheader = header or false })
end

local function create_array(t, inline, header)
  return setmetatable({ t },
    { __tomltype = "array", __jsontype = "array", __tomlinline = inline or false, __tomlheader = header or false })
end
-- ========== core functions ==========

--- get the char at current step or at custom position (not relative to cursor!)
---@param self table Parser
---@param at number|nil current step or at custom position (not relative to cursor!)
---@return string char the char at the requested place. empty string if out of bound
local function parser_get_char(self, at)
  at = at or self.cursor
  if not self.buffer[at] then
    return ""
  end

  return stringchar(self.buffer[at])
end

--- step the cursor from 1 step or custom steps (can be negative)
---@param self table Parser
---@param step number|nil next step (1) or custom steps (can be negative)
local function parser_step(self, step)
  self.cursor = self.cursor + (step or 1)
  self.pos = self.pos + (step or 1)
end

---act like step, but do not move the cursor. basically an handy fucntion to not type get_char(cursor+step)
---@param self table parser
---@param step number|nil next step (1) or custom steps (can be negative)
---@return string char the char at the effective step
local function parser_poke(self, step)
  local at = self.cursor + (step or 1)
  return self:get_char(at)
end

--- loop until cursor points at non white space char
---@param self table parser
local function parser_skip_ws(self)
  local char = self:get_char()
  while char == TAB or char == SPACE do
    self:step()
    char = self:get_char()
  end
end

--- checks if not out of bound of the buffer
---@param self table Parser
---@param step number|nil next step (1) or custom steps (can be negative)
---@return boolean in_of_bounds
local function parser_bound(self, step)
  local at = self.cursor + (step or 1)
  return at <= #self.buffer and at > 0
end

---throw an error catched by the "decode" function
---@param self table parser
---@param id any
local function parser_error(self, id)
  if not error_message[id] then
    error(id, 2)
  else
    error({
      id = id,
      message = error_message[id],
      line = self.line,
      pos = self.pos,
    })
  end
end

--- lines iterator
---@param self table parser
---@return function next
local function parser_lines(self)
  return function()
    return self:get_line()
  end
end

---get a line *shrug*
---@param self table parser
---@return string|nil line
---@return boolean is_crlf
local function parser_get_line(self)
  local line = ""

  while self:bound(0) do
    local nl, crlf = self:is_new_line()
    if nl then
      return line, crlf
    end
    line = line .. self:get_char()

    self:step()
  end
  if #line > 0 then -- the last line will not be skipped
    return line, false
  end

  return nil, false
end

---handle new line logic
---@param self table parser
---@param crlf boolean is_crlf (steps 2 or 1)
local function parser_new_line(self, crlf)
  self:step(crlf and 2 or 1)
  self.line = self.line + 1
  self.pos = 1
end

---check if the next chars (2 max) is a toml defined new line (CRLF or LF)
---@param self table parser
---@param steps number|nil
---@return boolean is_new_line
---@return boolean is_crlf
local function parser_is_new_line(self, steps)
  steps = steps or 0
  local char1 = self:poke(0 + steps)
  local char2 = self:poke(1 + steps)

  -- who tf use crlf excepts shitdows
  if (char1 == CR and char2 == LF) or char1 == LF then
    return true, char1 == CR
  end
  return false, false
end

local function Parser(buffer)
  -- look mom, oop!
  local parser = {
    cursor = 1,
    buffer = { stringbyte(buffer, 1, #buffer) },

    line = 1,
    pos = 1,

    parsed = {},

    -- members
    get_char = parser_get_char,
    get_line = parser_get_line,
    lines = parser_lines,
    step = parser_step,
    poke = parser_poke,
    new_line = parser_new_line,
    bound = parser_bound,
    skip_ws = parser_skip_ws,
    is_new_line = parser_is_new_line,

    error = parser_error,
  }

  parser.current = parser.parsed

  return parser
end

-- ========== parse functions ==========

local parse_string, parse_number, process_key, parse_header, parse_table_inline, parse_array_inline, parse_local_date, parse_local_time, parse_date, parse_key, parse_value, apply_kv

--TODO refactor and comment
parse_table_inline = function(parser)
  parser:step() -- consume {
  local t, current = {}, parser.current
  local table, valid = t, false
  local key, value, nxt
  local continue

  while parser:bound() do
    continue = false
    if parser:is_new_line() then
      parser:error(error_code.no_value)
    end

    parser:skip_ws()
    local char = parser:get_char()

    if char == "}" then
      valid = true
      parser:step()
      break
    elseif char == "," then
      if nxt then
        parser:error(error_code.invalid_bare_key_char)
      end

      apply_kv(parser, key, value, table)
      -- reset
      key, value, nxt = nil, nil, true
      table = t
    elseif not key then
      parser.current = table
      nxt = false

      key = parse_key(parser, true)

      table = parser.current
      parser.current = current

      continue = true
    else
      value = parse_value(parser, true)
      continue = true
    end

    if not continue then
      parser:step()
    end
  end

  if not valid then
    parser:error(error_code.invalid_inline_term)
  end
  if key then
    apply_kv(parser, key, value, table)
  end

  return create_table(t, true)
end

--TODO refactor and comment
parse_array_inline = function(parser)
  parser:step() -- consume [
  local table, current = create_array(nil, true), parser.current
  local valid, value = false, nil
  local index, nxt = 1, false

  local continue

  while parser:bound() do
    continue = false
    parser:skip_ws()
    local char = parser:get_char()

    local nl, crlf = parser:is_new_line()
    if nl then
      parser:new_line(crlf)
      continue = true
    elseif char == "]" then
      valid = true
      parser:step()
      break
    elseif char == "," then
      if nxt or index == 1 then
        parser:error(error_code.missing_value)
      end
      nxt = true
    elseif char == "#" then -- comments
      parser:get_line()
      continue = true
    else
      nxt = false
      value = parse_value(parser, true, true)
      apply_kv(parser, index, value, table)
      -- reset
      value = nil
      index = index + 1
      continue = true
    end

    if not continue then
      parser:step()
    end
  end

  if not valid then
    parser:error(error_code.invalid_inline_term)
  end
  if value then
    apply_kv(parser, index, value, table)
  end

  return table
end

parse_header = function(parser)
  -- goes back to the root
  parser.current = parser.parsed
  -- table = [...] array = [[...]]
  local array, key = false, nil
  local last_pos

  -- check header type and consume brackets
  if parser:poke() == "[" then
    array = true
    parser:step(2)
  else
    parser:step()
  end

  while parser:bound(0) do
    last_pos = parser.line .. ":" .. parser.pos
    if parser:is_new_line() then
      parser:error(error_code.expected_header_close_bracket)
    end

    local char = parser:get_char()

    if char == "]" then
      if array and parser:poke() ~= "]" then
        parser:error(error_code.expected_array_header_close_bracket)
      end

      -- consume close bracket
      parser:step(array and 2 or 1)
      break
    end

    -- parse key
    parser:skip_ws()
    key = parse_key(parser, true, true, array)
    parser.current = process_key(parser, key, parser.current, array, true, true)

    --TODO remove if not useful
    if last_pos == parser.line .. ":" .. parser.pos then
      error(("infinite loop at line %s:%s"):format(parser.line, parser.pos))
    end
  end -- loop

  if not key then
    parser:error(error_code.invalid_bare_key_char)
  end
end

parse_string = function(parser, can_multiline)
  local quote = parser:get_char()

  local litteral = (quote == "'")
  local multiline = false

  if can_multiline then
    if parser:poke(1) == quote and parser:poke(2) == quote then
      multiline = true
    end
  end

  -- consume the quote(s)
  if multiline then
    parser:step(3)
    -- if theres a new line after quotes, ignore it as it's multiline
    local nl, crlf = parser:is_new_line()
    if nl then
      parser:new_line(crlf)
    end
  else
    parser:step()
  end

  local str = ""
  local backslash = false
  -- if the loop exit for other reason than a quote, need to know if it was a valid reason to exit
  local closed = false
  local continue = false
  local last_pos

  while parser:bound(0) do
    last_pos = parser.line .. ":" .. parser.pos
    continue = false

    local char = parser:get_char()

    local nl, crlf = parser:is_new_line()
    if nl then -- throw an error if not multiline
      if not multiline then
        parser:error(error_code.invalid_string_term)
      else
        -- handle backslash at the end of line in multiline strings
        if backslash then
          parser:new_line(crlf)

          -- skip all empty line (ws and nl are empty lines)
          while parser:bound() do
            parser:skip_ws()
            local nl, crlf = parser:is_new_line()
            if not nl then
              break
            end

            if nl then
              parser:new_line(crlf)
            end
            parser:step()
          end -- loop

          parser:step(-1)
          continue = true
          backslash = false
        else
          str = str .. LF
          parser:new_line(crlf)
          continue = true
          parser:step(-1) -- don't consumes the next char (skipped by the step at the end of the loop)
        end
      end
      -- new line
    elseif backslash then
      if char == "u" or char == "U" then -- unicode yey
        local len = (char == "u") and 4 or 8
        local code = ""

        for i=1, len do
          parser:step()
          code = code .. parser:get_char()
        end
        
        if #code ~= len or not stringmatch(code, "^[0-9a-fA-F]+$") then
          parser:error(error_code.invalid_escape_utf8)
        end

        str = str .. utf8(tonumber(code, 16), parser)
       
      elseif (char == SPACE or char == TAB) and multiline then
        -- skip all empty line (ws and nl are empty lines)
        local seen_nl = false
        while parser:bound() do
          parser:skip_ws()
          local nl, crlf = parser:is_new_line()
          if not nl then
            if not seen_nl then
              parser:error(error_code.invalid_escape_char)
            end
            break
          end

          if nl then
            seen_nl = true
            parser:new_line(crlf)
          end
          parser:step()
        end -- loop

        parser:step(-1)
      else
        local seq = escape[char]
        if not seq then
          parser:error(error_code.invalid_escape_char)
        else
          str = str .. seq
        end
      end
      backslash = false
      continue = true
      -- backslash
    elseif char == quote then
      if multiline then
        -- stupid toml thing for having multiline string closing with 3, 4 or 5 quotes
        if parser:poke(1) == quote and parser:poke(2) == quote then
          for i = 0, 2 do
            parser:step()
            if parser:poke(2) == quote then
              str = str .. quote
            else
              break
            end
          end

          parser:step(1) -- consumes double quotes
          closed = true
          break
        end
      else
        -- not a multiline string, so it's valid
        closed = true
        break
      end
      -- quote
    elseif char == "\\" and not litteral and not backslash then
      backslash = true
      continue = true
    end

    -- don't include the current char, useful for escaped char
    if not continue then
      str = str .. validate_unicode(char, parser)
    end

    parser:step()

    --TODO remove if not useful
    if last_pos == parser.line .. ":" .. parser.pos then
      error(("infinite loop at line %s:%s"):format(parser.line, parser.pos))
    end
  end -- loop

  if not closed then
    parser:error(error_code.invalid_string_term)
  end

  -- consumes the last quote
  parser:step()
  return str
end

parse_number = function(buffer, parser)
  local old_pos = parser.pos
  parser.pos = parser.pos - #buffer

  if not stringmatch(stringsub(buffer, 1, 1), "[0-9-+in]") then
    return nil
  end

  local value, has_value

  if stringmatch(buffer, "^[%+%-]?inf$") then
    value = (stringsub(buffer, 1,1) == "-" and -mathinf) or mathinf
    has_value = true
  elseif stringmatch(buffer, "^[%+%-]?nan$") then
    value = mathnan
    has_value = true
  elseif stringmatch(buffer, "^0[xob].*$") then -- match hex, bin and oct escapes
    local f, num = stringmatch(buffer, "^0([xob])(.*)$")
    if f == "x" then                        -- hex
      if not stringmatch(num, "^[0-9a-fA-F_]+$") or stringmatch("_" .. num .. "_", "__") then
        parser:error(error_code.invalid_number_hex)
      else
        num = stringgsub(num, "_", "")
        has_value, value = pcall(tonumber, num, 16)
      end
    elseif f == "b" then -- binary
      if not stringmatch(num, "^[0-1_]+$") or stringmatch("_" .. num .. "_", "__") then
        parser:error(error_code.invalid_number_bin)
      else
        num = stringgsub(num, "_", "")
        has_value, value = pcall(tonumber, num, 2)
      end
    else -- octal
      if not stringmatch(num, "^[0-7_]+$") or stringmatch("_" .. num .. "_", "__") then
        parser:error(error_code.invalid_number_oct)
      else
        num = stringgsub(num, "_", "")
        has_value, value = pcall(tonumber, num, 8)
      end
    end -- f ==
  else  -- all the other nums
    -- tonumber is awesome, but toml wants to be the special kid and do things on his way, so let's follow
    local sign, number, is_exp, exp = stringmatch(buffer, "^([-+]?)([0-9%._]*[0-9]*)([eE]?)([-+0-9_]*)$")

    --     not a number            leading, trailing or double us             leading us on float           trailling us before float     leading dot                       trailling dot
    if not sign or #number <= 0 or stringmatch("_" .. number .. "_", "__") or stringmatch(number, "%._") or stringmatch(number, "_%.") or stringsub(number, 1, 1) == "." or stringsub(number, -1) == "." then
      parser:error(error_code.invalid_number)
    end


    if #is_exp > 0 then
      if stringmatch("_" .. exp .. "_", "__") or stringsub(exp, 1, 1) == "." or stringsub(exp, -1) == "." then
        parser:error(error_code.invalid_number_exp)
      end

      exp = stringgsub(exp, "_", "")
    elseif #exp > 0 then
      parser:error(error_code.invalid_number_exp)
    end

    number = stringgsub(number, "_", "")
    -- checks for leading 0
    if stringmatch(number, "^0+[0-9]+") then
      parser:error(error_code.invalid_number)
    end

    --TODO checks for integer imprecision with non exponent numbers

    has_value, value = pcall(tonumber, sign .. number .. is_exp .. exp)
  end

  if not has_value or not value then
    parser:error(error_code.invalid_number)
  end
  parser.pos = old_pos
  return value
end

parse_local_date = function(input, parser)
  local y, m, d = stringmatch(input, match_date)

  local data = { __type = "localdate", input = input, timestamp = 0 }
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or not m or not d then
    parser:error(error_code.invalid_local_date)
    return {} -- to reassure the linter about error checking, even so "error" stops the code
  end

  local _date = { year = y, month = m, day = d, hour = 1, min = 0, sec = 0 }
  validate_date(_date, parser) -- throw if not valid
  data.timestamp = os.time(_date)
  -- convert to ms
  data.timestamp = data.timestamp * 1e3

  return setmetatable(data, date_meta)
end

parse_local_time = function(input, parser)
  local h, m, s, ms = stringmatch(input, match_time)

  local data = { __type = "localtime", input = input }
  local _date = { year = 1970, month = 1, day = 1, hour = tonumber(h), min = tonumber(m), sec = tonumber(s) }
  validate_date(_date, parser) -- throw if not valid
  data.timestamp = os.time(_date)
  -- convert to ms
  data.timestamp = data.timestamp * 1e3
  data.timestamp = data.timestamp + math.floor((tonumber(ms) or 0) * 1e3)


  return setmetatable(data, date_meta)
end

parse_date = function(input, parser)
  local time = stringmatch(input, pattern_ltime)
  if time then
    return parse_local_time(time, parser)
  end

  local date = stringmatch(input, pattern_ldate)
  if date then
    return parse_local_date(date, parser)
  end

  local date, sep, time, sep_off, offset = stringmatch(input, pattern_date)


  if not date then
    parser:error(error_code.invalid_date)
    return {} -- to reassure the linter about error checking, even so "error" stops the code
  end

  local data = { __type = "datetime", timestamp = 0, input = input }
  local date_data = parse_local_date(date, parser)
  local time_data = parse_local_time(time, parser)

  data.timestamp = date_data.timestamp + time_data.timestamp
  date_data, time_data = nil, nil

  local h_off, m_off = stringmatch(offset, match_offset)
  if not h_off and stringmatch(sep_off, "[%+%-]") then
    parser:error(error_code.invalid_date_offset)
    return {} -- to reassure the linter about error checking, even so "error" stops the code
  end

  if sep_off == "Z" or sep_off == "z" or sep_off == "" then
    h_off, m_off = 0, 0
  elseif sep_off == "-" then
    h_off, m_off = -tonumber(h_off), -tonumber(m_off)
  else
    h_off, m_off = tonumber(h_off), tonumber(m_off)
  end

  data.offset = (h_off * 60 * 60 * 1000) + (m_off * 60 * 1000)
  data.timestamp = data.timestamp + (data.offset or 0)

  if sep_off == "" then data.offset = nil end

  return setmetatable(data, date_meta)
end

process_key = function(parser, key, root, is_array, is_last, is_header)
  local root_meta = getmetatable(root)
  local key_meta = getmetatable(root[key])

  -- checks if trying to apply to inline table/array or header
  do
    if is_last then
      local meta = key_meta
      if meta and meta.__tomlheader and meta.__tomltype == "table" then
        parser:error(error_code.redefine)
      end
    end

    local meta = is_array and root_meta or key_meta
    if meta and meta.__tomlinline then
      parser:error(error_code.redefine_inline)
    end
  end

  if is_array then
    if #root > 0 then
      if type(root[#root][key]) == "table" then
        if #root[#root][key] > 0 then
          root[#root][key][#root[#root][key] + 1] = {}
          return root[#root][key][#root[#root][key]]
        else
          parser:error(error_code.redefine)
        end
      elseif root[#root][key] == nil then
        root[#root][key] = create_array(create_table(nil, nil, is_header), nil, is_header)
        return root[#root][key][1]
      else
        parser:error(error_code.redefine)
      end
    elseif root[key] == nil then
      if is_last then
        root[key] = create_array(create_table(nil, nil, is_header), nil, is_header)
        return root[key][1]
      end

      root[key] = create_table(nil, nil, false)
      return root[key]
    elseif type(root[key]) == "table" then
      if #root[key] <= 0 and is_last then
        parser:error(error_code.redefine)
      end

      if is_last then
        root[key][#root[key] + 1] = create_table(nil, nil, is_header)
        return root[key][#root[key]]
      end

      return root[key]
    else
      parser:error(error_code.redefine)
    end
  else -- is_table
    if #root > 0 then
      if is_last then
        if root[#root][key] ~= nil then
          parser:error(error_code.redefine)
        else
          root[#root][key] = create_table(nil, nil, is_header)
          return root[#root][key]
        end
      else
        if type(root[#root][key]) == "table" then
          return root[#root][key]
        else
          parser:error(error_code.redefine)
        end
      end
    elseif root[key] == nil then
      root[key] = create_table(nil, nil, is_last and is_header)
      return root[key]
    elseif type(root[key]) == "table" then
      if #root[key] > 0 and is_last then
        parser:error(error_code.redefine)
      end

      if is_last then
        root[key] = create_table(root[key], nil, is_header)
      end
      if key_meta.__tomltype == "array" and not is_header then
        parser:error(error_code.redefine)
      end
      if is_header and is_last and not is_table_empty(root[key]) then
        parser:error(error_code.redefine)
      end
      return root[key]
    else
      parser:error(error_code.redefine)
    end
  end
end

parse_key = function(parser, inline, is_header, is_array)
  local key, key_end = nil, false
  local seen_ws, seen_char = false, false
  local continue

  while parser:bound(0) do
    continue = false
    -- a new line here means that there is a missing piece ( "=", "]" for inline)
    if parser:is_new_line() then
      parser:error(inline and error_code.expected_header_close_bracket or error_code.no_value)
    end

    local char = parser:get_char()

    if char == "=" and not is_header then
      parser:step() -- consumes the =
      break
    elseif (char == "]" or char == "}") and inline then
      -- should not consume it as parse_header need it to flags the end of the header
      break
    end

    if char == "." then
      if not seen_char and not key_end then
        parser:error(error_code.invalid_bare_key_char)
      end

      parser.current = process_key(parser, key, parser.current, is_array, false, is_header)

      key, key_end = "", false
      seen_char, seen_ws = false, false
    elseif key_end then
      parser:error(error_code.expected_dot)
    elseif stringmatch(char, pattern_quote) then
      if seen_char then
        parser:error(error_code.invalid_bare_key_char)
      end
      key = parse_string(parser, false)
      parser:skip_ws()
      seen_char, key_end, continue = true, true, true
    else
      if char == SPACE or char == TAB then
        if seen_char then seen_ws = true end
      elseif stringmatch(char, pattern_barkey) then
        if seen_ws and seen_char then
          parser.pos = parser.pos - 1
          parser:error(error_code.invalid_bare_key_ws)
        end
        key = (key or "") .. char
        seen_char = true
      else
        parser:error(error_code.invalid_bare_key_char)
      end
    end

    if not continue then
      parser:step()
    end
  end -- loop

  return key
end

parse_value = function(parser, inline, is_array)
  local value

  while parser:bound() do
    local char = parser:get_char()

    if stringmatch(char, pattern_quote) then
      value = parse_string(parser, true)
      break
    elseif char == "[" then
      value = parse_array_inline(parser)
      break
    elseif char == "{" then
      value = parse_table_inline(parser)
      break
    else
      -- number date or boolean
      -- get the value, and try to guess by poking around

      --TODO refactor and reallocate number parsing to his own function
      -- insanely awful
      parser:skip_ws()
      local buffer_pos = parser.pos
      local buffer = ""

      if inline then -- get the buffer until eol, ",", "]" or "}"
        while parser:bound() do
          char = parser:get_char()
          local nl, crlf = parser:is_new_line()
          if nl then
            if not is_array then
              parser:error(error_code.no_value)
            else
              parser:new_line(crlf)
              parser:step(-1)
            end
          end

          if char == "#" then
            parser:get_line()
            parser:step(-1)
          end
          if char == "," or char == "}" or char == "]" then
            break
          end

          buffer = buffer .. char

          parser:step()
        end
      else
        buffer = parser:get_line()
      end

      -- clean the string and remove comments
      buffer = stringtrim(stringgsub(buffer, "#.-$", ""))

      -- try for a boolean
      if buffer == "true" then
        value = true
      elseif buffer == "false" then
        value = false
      else
        -- it's pattern time !
        -- ugly af
        if stringmatch(buffer, pattern_date) then
          local current_pos = parser.pos
          parser.pos = buffer_pos
          value = parse_date(buffer, parser)
          parser.pos = current_pos
        elseif stringmatch(buffer, pattern_ldate) then
          local current_pos = parser.pos
          parser.pos = buffer_pos
          value = parse_local_date(buffer, parser)
          parser.pos = current_pos
        elseif stringmatch(buffer, pattern_ltime) then
          local current_pos = parser.pos
          parser.pos = buffer_pos
          value = parse_local_time(buffer, parser)
          parser.pos = current_pos
        else
          value = parse_number(buffer, parser)

          if not value then
            parser.pos = buffer_pos
            parser:error(error_code.invalid_value)
          end
        end
      end
      break
    end


    parser:step()
  end -- loop

  return value
end

apply_kv = function(parser, key, value, tbl)
  if key and value == nil then
    parser:error(error_code.missing_value)
  end
  if tbl[key] ~= nil then
    parser:error(error_code.redefine)
  end

  tbl[key] = value
end

local function parse_toml(buffer)
  local parser = Parser(buffer)

  local key, value
  -- used when key specify a table (eg path.to.key = value), it pollutes parser.current and override the current header
  local current_header = parser.parsed
  -- means that nothing is expected until end of line excepts comments or white spaces
  local line_end = false
  -- I hate lua5.1 for not having goto statement or simply a continue keyword
  local continue = false
  -- just in case, to avoid infinite loops
  local last_pos


  -- while cursor points at a valid value
  while parser:bound(0) do
    continue = false
    last_pos = parser.line .. ":" .. parser.pos

    -- cleans white spaces
    parser:skip_ws()

    local char = parser:get_char()

    local nl, crlf = parser:is_new_line()
    if nl then -- new line babe
      if line_end and key then
        apply_kv(parser, key, value, parser.current)
        key, value = nil, nil
        parser.current = current_header
      end

      parser:new_line(crlf)

      -- the cursor is placed to the first pos of the next line
      continue, line_end = true, false
    elseif char == "#" then -- comments
      parser:get_line()
      -- get_line actually stops the cursor at the lf/crlf char and do not apply new line logic by himself
      continue = true
    elseif line_end then                -- should be nothing expect comments, ws or new line, that are hanlded earlier in the loop
      parser:error(error_code.expected_comment_or_ws)
    elseif char == "[" and not key then -- table and array header
      -- sets parser.current to the header
      parse_header(parser)
      current_header = parser.current
      --  parser_header stops after the close bracket
      continue, line_end = true, true
    else -- key-value
      if not key then
        key = parse_key(parser)
      else
        value = parse_value(parser)
        line_end = true
      end
      continue = true
    end



    -- if some operations place the cursor to the actual next step, continue avoid to take
    -- another step, which would ignore the preceding step
    if not continue then
      parser:step()
    end


    --TODO remove if not useful
    if last_pos == parser.line .. ":" .. parser.pos then
      error(("infinite loop at line %s:%s"):format(parser.line, parser.pos))
    end
  end -- loop

  if key then
    apply_kv(parser, key, value, parser.current)
  end

  return parser.parsed
end

-- ========== export ==========

local function decode(toml)
  if type(toml) ~= "string" then
    error("Expected string to parse, got " .. type(toml))
  end

  local status, err = pcall(parse_toml, toml)

  if not status then
    if type(err) ~= "table" then
      error(err)
    end
    return nil, err.message and err.message:format(err.line or -1, err.pos or -1), err
  end -- status

  return err
end

local function encode()

end

return {
  error_code = error_code,
  error_message = error_message,

  encode = encode,
  decode = decode,
  parse = decode,

  version = "0.1.0"
}
