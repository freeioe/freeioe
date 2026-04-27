--- TOML 1.0.0 Parser and Serializer for Lua 5.4 (Single File Version)
-- Pure Lua implementation of TOML 1.0.0 specification
-- This file combines all modules into one for easy integration

-- ============================================================================
-- ERROR MODULE
-- ============================================================================

local toml_error = {}

--- ParseError: Represents a parsing error with location information
toml_error.ParseError = {}
toml_error.ParseError.__index = toml_error.ParseError

--- Create a new ParseError
-- @param msg string Error message
-- @param line number Line number (1-based)
-- @param column number Column number (1-based)
-- @return table ParseError object
function toml_error.ParseError.new(msg, line, column)
  return setmetatable({
    type = "ParseError",
    message = msg or "Parse error",
    line = line or 1,
    column = column or 1
  }, toml_error.ParseError)
end

--- ValidationError: Represents a validation error with path information
toml_error.ValidationError = {}
toml_error.ValidationError.__index = toml_error.ValidationError

--- Create a new ValidationError
-- @param msg string Error message
-- @param path table Array of path components (e.g., {"users", "admin"})
-- @return table ValidationError object
function toml_error.ValidationError.new(msg, path)
  return setmetatable({
    type = "ValidationError",
    message = msg or "Validation error",
    path = path or {}
  }, toml_error.ValidationError)
end

--- Format error object to string
-- @param err table|nil|string Error object
-- @return string Formatted error message
function toml_error.to_string(err)
  if err == nil then
    return "Unknown error"
  end

  if type(err) == "string" then
    return err
  end

  if err.type == "ParseError" then
    return string.format("Parse error at line %d, column %d: %s",
      err.line, err.column, err.message)
  end

  if err.type == "ValidationError" then
    local path_str = table.concat(err.path, ".")
    return string.format("Validation error at %s: %s", path_str, err.message)
  end

  return tostring(err.message or err)
end

--- Generate context snippet for error location
-- @param input string Full input text
-- @param line number Line number (1-based)
-- @param column number Column number (1-based)
-- @return string Context snippet with pointer
function toml_error.generate_context(input, line, column)
  if not input or line < 1 then
    return ""
  end

  -- Split input into lines
  local lines = {}
  for l in input:gmatch("[^\r\n]+") do
    table.insert(lines, l)
  end

  -- Get the error line (1-based index)
  local error_line = lines[line]
  if not error_line then
    return ""
  end

  -- Build pointer with carets
  local pointer = string.rep(" ", column - 1) .. "^"

  -- Format context
  local context = string.format("  | %s\n  | %s", error_line, pointer)

  return context
end

-- ============================================================================
-- DATETIME MODULE
-- ============================================================================

local datetime = {}

--- DateTime types
local TYPE_OFFSET = "datetime_offset"
local TYPE_LOCAL = "datetime_local"
local TYPE_DATE = "date_local"
local TYPE_TIME = "time_local"

--- Parse an offset date-time (RFC 3339 with offset)
-- Format: 1979-05-27T07:32:00Z or 1979-05-27T07:32:00.123456-08:00
-- @param str string DateTime string
-- @return table|nil Parsed datetime or nil on error
function datetime.parse_offset(str)
  -- Pattern: YYYY-MM-DDTHH:MM:SS[.ffffffff]Z
  -- Pattern: YYYY-MM-DDTHH:MM:SS[.ffffffff]±HH:MM
  local pattern = "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?(%d*)Z?$"
  local year, month, day, hour, min, sec, frac = str:match(pattern)

  if year then
    return {
      type = TYPE_OFFSET,
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      nanosec = datetime._parse_frac(frac),
      offset = "Z"
    }
  end

  -- Try with offset ±HH:MM
  pattern = "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?(%d*)([+-])(%d%d):(%d%d)$"
  year, month, day, hour, min, sec, frac, sign, off_hour, off_min = str:match(pattern)

  if year then
    return {
      type = TYPE_OFFSET,
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      nanosec = datetime._parse_frac(frac),
      offset = string.format("%s%02d:%02d", sign, tonumber(off_hour), tonumber(off_min))
    }
  end

  return nil
end

--- Parse a local date-time (RFC 3339 without offset)
-- Format: 1979-05-27T07:32:00.123456
-- @param str string DateTime string
-- @return table|nil Parsed datetime or nil on error
function datetime.parse_local(str)
  -- Pattern: YYYY-MM-DDTHH:MM:SS[.ffffffff]
  local pattern = "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?(%d*)$"
  local year, month, day, hour, min, sec, frac = str:match(pattern)

  if year then
    return {
      type = TYPE_LOCAL,
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      nanosec = datetime._parse_frac(frac)
    }
  end

  return nil
end

--- Parse a local date
-- Format: 1979-05-27
-- @param str string Date string
-- @return table|nil Parsed date or nil on error
function datetime.parse_date(str)
  -- Pattern: YYYY-MM-DD
  local pattern = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"
  local year, month, day = str:match(pattern)

  if year then
    return {
      type = TYPE_DATE,
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day)
    }
  end

  return nil
end

--- Parse a local time
-- Format: 07:32:00.123456
-- @param str string Time string
-- @return table|nil Parsed time or nil on error
function datetime.parse_time(str)
  -- Pattern: HH:MM:SS[.ffffffff]
  local pattern = "^(%d%d):(%d%d):(%d%d)%.?(%d*)$"
  local hour, min, sec, frac = str:match(pattern)

  if hour then
    return {
      type = TYPE_TIME,
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      nanosec = datetime._parse_frac(frac)
    }
  end

  return nil
end

--- Parse any TOML datetime format
-- @param str string DateTime string
-- @return table|nil Parsed datetime or nil on error
function datetime.parse(str)
  -- Check for T separator (datetime vs date/time)
  local has_t = str:find("T") ~= nil

  -- Check for offset indicator
  local has_offset = str:match("[+-]%d%d:%d%d$") or str:match("Z$")

  -- Parse based on format
  if has_t then
    -- Has T: date-time
    if has_offset then
      return datetime.parse_offset(str)
    else
      return datetime.parse_local(str)
    end
  else
    -- No T: either date or time
    -- Try date first (YYYY-MM-DD pattern)
    if str:match("^%d%d%d%d%-%d%d%-%d%d$") then
      return datetime.parse_date(str)
    else
      return datetime.parse_time(str)
    end
  end
end

--- Parse fractional seconds to nanoseconds
-- @param frac string Fractional part (may be empty)
-- @return number Nanoseconds (0-999999999)
function datetime._parse_frac(frac)
  if not frac or frac == "" then
    return 0
  end

  -- Pad or truncate to 9 digits (nanoseconds)
  frac = frac .. string.rep("0", 9 - #frac):sub(1, 9 - #frac)
  frac = frac:sub(1, 9)

  return tonumber(frac) or 0
end

--- Serialize a datetime table to TOML format
-- @param dt table DateTime table
-- @return string|nil TOML datetime string or nil on error
function datetime.serialize(dt)
  if not dt or not dt.type then
    return nil
  end

  if dt.type == TYPE_OFFSET then
    return datetime._serialize_offset(dt)
  elseif dt.type == TYPE_LOCAL then
    return datetime._serialize_local(dt)
  elseif dt.type == TYPE_DATE then
    return datetime._serialize_date(dt)
  elseif dt.type == TYPE_TIME then
    return datetime._serialize_time(dt)
  end

  return nil
end

--- Serialize offset date-time to TOML format
-- @param dt table DateTime table
-- @return string TOML datetime string
function datetime._serialize_offset(dt)
  local date_part = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
  local time_part = string.format("%02d:%02d:%02d", dt.hour, dt.min, dt.sec)

  local result = date_part .. "T" .. time_part

  -- Add fractional seconds if present
  if dt.nanosec and dt.nanosec > 0 then
    result = result .. string.format(".%09d", dt.nanosec):gsub("0+$", "")
  end

  -- Add offset
  if dt.offset then
    result = result .. dt.offset
  else
    result = result .. "Z"
  end

  return result
end

--- Serialize local date-time to TOML format
-- @param dt table DateTime table
-- @return string TOML datetime string
function datetime._serialize_local(dt)
  local date_part = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
  local time_part = string.format("%02d:%02d:%02d", dt.hour, dt.min, dt.sec)

  local result = date_part .. "T" .. time_part

  -- Add fractional seconds if present
  if dt.nanosec and dt.nanosec > 0 then
    result = result .. string.format(".%09d", dt.nanosec):gsub("0+$", "")
  end

  return result
end

--- Serialize local date to TOML format
-- @param dt table Date table
-- @return string TOML date string
function datetime._serialize_date(dt)
  return string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
end

--- Serialize local time to TOML format
-- @param dt table Time table
-- @return string TOML time string
function datetime._serialize_time(dt)
  local result = string.format("%02d:%02d:%02d", dt.hour, dt.min, dt.sec)

  -- Add fractional seconds if present
  if dt.nanosec and dt.nanosec > 0 then
    result = result .. string.format(".%09d", dt.nanosec):gsub("0+$", "")
  end

  return result
end

--- Validate a datetime table
-- @param dt table DateTime table
-- @return boolean True if valid
function datetime.validate(dt)
  if not dt or not dt.type then
    return false
  end

  -- Check required fields based on type
  if dt.type == TYPE_OFFSET or dt.type == TYPE_LOCAL then
    if not dt.year or not dt.month or not dt.day then
      return false
    end
    if not dt.hour or not dt.min or not dt.sec then
      return false
    end
  elseif dt.type == TYPE_DATE then
    if not dt.year or not dt.month or not dt.day then
      return false
    end
  elseif dt.type == TYPE_TIME then
    if not dt.hour or not dt.min or not dt.sec then
      return false
    end
  else
    return false
  end

  -- Validate ranges
  if dt.month and (dt.month < 1 or dt.month > 12) then
    return false
  end

  if dt.day and (dt.day < 1 or dt.day > 31) then
    return false
  end

  if dt.hour and (dt.hour < 0 or dt.hour > 23) then
    return false
  end

  if dt.min and (dt.min < 0 or dt.min > 59) then
    return false
  end

  if dt.sec and (dt.sec < 0 or dt.sec > 60) then -- 60 for leap second
    return false
  end

  if dt.nanosec and (dt.nanosec < 0 or dt.nanosec > 999999999) then
    return false
  end

  return true
end

--- Create a current offset date-time
-- @return table DateTime table for now (UTC)
function datetime.now()
  local now = os.time(os.date("!*t"))  -- UTC
  local date = os.date("!*t", now)

  return {
    type = TYPE_OFFSET,
    year = date.year,
    month = date.month,
    day = date.day,
    hour = date.hour,
    min = date.min,
    sec = date.sec,
    nanosec = 0,
    offset = "Z"
  }
end

-- Export type constants
datetime.TYPE_OFFSET = TYPE_OFFSET
datetime.TYPE_LOCAL = TYPE_LOCAL
datetime.TYPE_DATE = TYPE_DATE
datetime.TYPE_TIME = TYPE_TIME

-- ============================================================================
-- AST MODULE
-- ============================================================================

local ast = {}

--- AST node types
ast.NodeType = {
  DOCUMENT = "Document",
  TABLE = "Table",
  KEY_VALUE = "KeyValue",
  ARRAY = "Array",
  INLINE_TABLE = "InlineTable",
  STRING = "String",
  INTEGER = "Integer",
  FLOAT = "Float",
  BOOLEAN = "Boolean",
  DATETIME = "DateTime",
}

--- Create a document node
-- @return table Document node
function ast.document()
  return {
    type = ast.NodeType.DOCUMENT,
    tables = {},  -- Map of table key path to table node
    root = ast.table()
  }
end

--- Create a table node
-- @param string|table key The table key (string or array of strings for dotted keys)
-- @return table Table node
function ast.table(key)
  return {
    type = ast.NodeType.TABLE,
    key = key or "",
    values = {},  -- Map of key to value node
    is_array = false  -- True if this is an array of tables element
  }
end

--- Create a key-value node
-- @param table key The key (array of strings for dotted keys)
-- @param table value The value node
-- @return table Key-value node
function ast.key_value(key, value)
  return {
    type = ast.NodeType.KEY_VALUE,
    key = key,
    value = value
  }
end

--- Create an array node
-- @param table values Array of value nodes
-- @return table Array node
function ast.array(values)
  return {
    type = ast.NodeType.ARRAY,
    values = values or {}
  }
end

--- Create an inline table node
-- @param table values Map of key to value nodes
-- @return table Inline table node
function ast.inline_table(values)
  return {
    type = ast.NodeType.INLINE_TABLE,
    values = values or {}
  }
end

--- Create a string node
-- @param string value The string value
-- @param string quote_type The quote type ("basic", "literal", "ml_basic", "ml_literal")
-- @return table String node
function ast.string(value, quote_type)
  return {
    type = ast.NodeType.STRING,
    value = value,
    quote_type = quote_type or "basic"
  }
end

--- Create an integer node
-- @param number value The integer value
-- @param string base The number base ("10", "16", "8", "2")
-- @return table Integer node
function ast.integer(value, base)
  return {
    type = ast.NodeType.INTEGER,
    value = value,
    base = base or "10"
  }
end

--- Create a float node
-- @param number value The float value
-- @return table Float node
function ast.float(value)
  return {
    type = ast.NodeType.FLOAT,
    value = value
  }
end

--- Create a boolean node
-- @param boolean value The boolean value
-- @return table Boolean node
function ast.boolean(value)
  return {
    type = ast.NodeType.BOOLEAN,
    value = value
  }
end

--- Create a datetime node
-- @param table value Datetime components
-- @param string datetime_type Type of datetime ("offset", "local", "date", "time")
-- @return table DateTime node
function ast.datetime(value, datetime_type)
  return {
    type = ast.NodeType.DATETIME,
    value = value,
    datetime_type = datetime_type or "offset"
  }
end

-- ============================================================================
-- LEXER MODULE
-- ============================================================================

local Lexer = {}
Lexer.__index = Lexer

--- Create a new lexer
-- @param input string TOML input text
-- @return table Lexer object
function Lexer.new(input)
  return setmetatable({
    input = input or "",
    pos = 1,
    line = 1,
    column = 1,
    peeked_token = nil
  }, Lexer)
end

--- Get current character
-- @return string|nil Current character or nil
function Lexer:current()
  if self.pos > #self.input then
    return nil
  end
  return self.input:sub(self.pos, self.pos)
end

--- Peek ahead at next character
-- @param number offset Number of characters to peek ahead (default 1)
-- @return string|nil Character at offset or nil
function Lexer:peek(offset)
  offset = offset or 1
  return self.input:sub(self.pos + offset, self.pos + offset)
end

--- Advance to next character
-- @return string Character that was advanced past
function Lexer:advance()
  local ch = self:current()
  self.pos = self.pos + 1

  if ch == "\n" then
    self.line = self.line + 1
    self.column = 1
  else
    self.column = self.column + 1
  end

  return ch
end

--- Skip whitespace (space and tab only, not newlines)
function Lexer:skip_whitespace()
  while self:current() == " " or self:current() == "\t" do
    self:advance()
  end
end

--- Check if at end of input
-- @return boolean True if at EOF
function Lexer:is_eof()
  return self.pos > #self.input
end

--- Create a token
-- @param token_type string Token type
-- @param value any Token value
-- @return table Token object
function Lexer:token(token_type, value)
  return {
    type = token_type,
    value = value,
    line = self.token_line or self.line,
    column = self.token_column or self.column
  }
end

--- Lex an identifier (bare key)
-- @return table|nil Token or nil if not an identifier
function Lexer:lex_identifier()
  local start_pos = self.pos
  local start_col = self.column
  local start_line = self.line

  -- Bare keys: ASCII letters, digits, underscore, dash
  local ch = self:current()
  if not (ch:match("[A-Za-z_]") or (ch:match("[0-9]") and self.pos > start_pos)) then
    return nil
  end

  local value = ""
  while self:current() do
    ch = self:current()
    if ch:match("[A-Za-z0-9_-]") then
      value = value .. ch
      self:advance()
    else
      break
    end
  end

  if #value == 0 then
    return nil
  end

  -- Check for reserved keywords (boolean)
  if value == "true" or value == "false" then
    return self:token("boolean", value == "true")
  end

  -- Check for special float values
  if value == "inf" or value == "nan" then
    return self:token("float", self:parse_special_float(value))
  end

  return self:token("identifier", value)
end

--- Parse special float values (inf, nan)
-- @param value string The string value
-- @return number Float value
function Lexer:parse_special_float(value)
  if value == "inf" then
    return math.huge
  elseif value == "nan" then
    return 0 / 0 -- NaN
  end
  return 0 / 0
end

--- Lex a number (integer or float)
-- @return table|nil Token or nil if not a number
function Lexer:lex_number()
  local start_pos = self.pos
  local start_line = self.line
  local start_col = self.column

  local ch = self:current()

  -- Check for sign
  local has_sign = false
  if ch == "+" or ch == "-" then
    has_sign = true
    self:advance()
    ch = self:current()
  end

  -- Check for special float values
  if ch == "i" or ch == "n" then
    local value = ""
    while self:current() and self:current():match("[a-z]") do
      value = value .. self:current()
      self:advance()
    end

    if value == "inf" or value == "nan" then
      local num_value = self:parse_special_float(value)
      if has_sign and value == "inf" then
        -- Handle +inf and -inf
        local sign = self.input:sub(start_pos, start_pos)
        if sign == "-" then
          num_value = -math.huge
        else
          num_value = math.huge
        end
      end
      return self:token("float", num_value)
    end

    -- Not a special value, rewind
    self.pos = start_pos
    self.column = start_col
    return nil
  end

  -- Check for base prefixes
  local base = 10
  if ch == "0" then
    local next_ch = self:peek()
    if next_ch == "x" or next_ch == "X" then
      base = 16
      self:advance()
      self:advance()
    elseif next_ch == "o" or next_ch == "O" then
      base = 8
      self:advance()
      self:advance()
    elseif next_ch == "b" or next_ch == "B" then
      base = 2
      self:advance()
      self:advance()
    end
  end

  -- Collect digits and underscores
  local value = ""
  local has_digit = false
  local has_underscore = false

  while self:current() do
    ch = self:current()
    if base == 10 and ch:match("[0-9]") then
      value = value .. ch
      has_digit = true
      self:advance()
    elseif base == 16 and ch:match("[0-9a-fA-F]") then
      value = value .. ch
      has_digit = true
      self:advance()
    elseif base == 8 and ch:match("[0-7]") then
      value = value .. ch
      has_digit = true
      self:advance()
    elseif base == 2 and ch:match("[01]") then
      value = value .. ch
      has_digit = true
      self:advance()
    elseif ch == "_" then
      has_underscore = true
      self:advance()
    else
      break
    end
  end

  if not has_digit then
    self.pos = start_pos
    self.column = start_col
    return nil
  end

  -- Remove underscores for conversion
  local clean_value = value:gsub("_", "")

  -- Check if it's a float
  local next_ch = self:current()
  if next_ch == "." then
    -- Float with fractional part
    local peek1 = self:peek(1)
    if peek1 and peek1:match("[0-9]") then
      local is_negative = has_sign and self.input:sub(start_pos, start_pos) == "-"
      return self:lex_float_fractional(clean_value, start_pos, start_col, is_negative)
    end
  end

  if next_ch == "e" or next_ch == "E" then
    -- Float with exponent part
    local is_negative = has_sign and self.input:sub(start_pos, start_pos) == "-"
    return self:lex_float_exponent(clean_value, start_pos, start_col, is_negative)
  end

  -- It's an integer
  local num_value = tonumber(clean_value, base)
  if has_sign then
    local sign = self.input:sub(start_pos, start_pos)
    if sign == "-" then
      num_value = -num_value
    end
  end

  return self:token("integer", num_value)
end

--- Lex a float with fractional part
-- @param int_part string Integer part as string
-- @param start_pos number Starting position (for error recovery)
-- @param start_col number Starting column (for error recovery)
-- @param is_negative boolean Whether the number is negative
-- @return table Float token
function Lexer:lex_float_fractional(int_part, start_pos, start_col, is_negative)
  self:advance() -- Skip the decimal point

  local frac_part = ""
  while self:current() and self:current():match("[0-9]") do
    frac_part = frac_part .. self:current()
    self:advance()
  end

  local value_str = int_part .. "." .. frac_part
  local value = tonumber(value_str)
  if not value then
    self.pos = start_pos
    return nil
  end

  -- Apply negative sign
  if is_negative then
    value = -value
  end

  -- Check for exponent
  if self:current() == "e" or self:current() == "E" then
    local exp_token = self:lex_float_exponent(tostring(value), start_pos, start_col)
    if exp_token then
      return exp_token
    end
  end

  return self:token("float", value)
end

--- Lex a float with exponent part
-- @param base_str string Base number as string
-- @param start_pos number Starting position (for error recovery)
-- @param start_col number Starting column (for error recovery)
-- @param is_negative boolean Whether the base number is negative
-- @return table Float token
function Lexer:lex_float_exponent(base_str, start_pos, start_col, is_negative)
  self:advance() -- Skip 'e' or 'E'

  local exp_str = ""

  -- Optional sign in exponent (this is separate from the base sign)
  if self:current() == "+" or self:current() == "-" then
    exp_str = exp_str .. self:current()
    self:advance()
  end

  -- Digits
  while self:current() and self:current():match("[0-9]") do
    exp_str = exp_str .. self:current()
    self:advance()
  end

  local value_str = base_str .. "e" .. exp_str
  local value = tonumber(value_str)
  if not value then
    self.pos = start_pos
    return nil
  end

  -- Apply negative sign from the base number
  if is_negative then
    value = -value
  end

  return self:token("float", value)
end

--- Lex a basic string (double-quoted)
-- @return table|nil Token or nil if not a string
function Lexer:lex_string_basic()
  if self:current() ~= '"' then
    return nil
  end

  local start_col = self.column
  self:advance() -- Skip opening quote

  -- Check for multi-line string
  if self:current() == '"' and self:peek() == '"' then
    return self:lex_string_ml_basic()
  end

  local value = ""
  while self:current() do
    local ch = self:current()

    if ch == "\\" then
      self:advance()
      local escape = self:current()

      if escape == "b" then
        value = value .. "\b"
      elseif escape == "t" then
        value = value .. "\t"
      elseif escape == "n" then
        value = value .. "\n"
      elseif escape == "f" then
        value = value .. "\f"
      elseif escape == "r" then
        value = value .. "\r"
      elseif escape == '"' then
        value = value .. '"'
      elseif escape == "\\" then
        value = value .. "\\"
      elseif escape == "u" then
        -- Unicode escape \uXXXX
        local hex = ""
        for i = 1, 4 do
          self:advance()
          if not self:current() or not self:current():match("[0-9a-fA-F]") then
            return nil -- Invalid unicode escape
          end
          hex = hex .. self:current()
        end
        value = value .. utf8.char(tonumber(hex, 16))
      elseif escape == "U" then
        -- Unicode escape \UXXXXXXXX
        local hex = ""
        for i = 1, 8 do
          self:advance()
          if not self:current() or not self:current():match("[0-9a-fA-F]") then
            return nil -- Invalid unicode escape
          end
          hex = hex .. self:current()
        end
        value = value .. utf8.char(tonumber(hex, 16))
      else
        -- Unknown escape, treat as literal
        value = value .. escape
      end

      self:advance()
    elseif ch == '"' then
      self:advance() -- Skip closing quote
      return self:token("string_basic", value)
    else
      value = value .. ch
      self:advance()
    end
  end

  return nil -- Unclosed string
end

--- Lex a multi-line basic string
-- @return table Multi-line string token
function Lexer:lex_string_ml_basic()
  self:advance() -- Skip second quote
  self:advance() -- Skip third quote

  local value = ""

  -- Skip first newline if present
  if self:current() == "\r" or self:current() == "\n" then
    if self:current() == "\r" then
      self:advance()
    end
    if self:current() == "\n" then
      self:advance()
    end
  end

  while self:current() do
    local ch = self:current()

    if ch == "\\" then
      self:advance()
      local next_ch = self:current()

      -- Line ending backslash
      if next_ch == "\r" or next_ch == "\n" then
        if next_ch == "\r" then
          self:advance()
        end
        if self:current() == "\n" then
          self:advance()
        end
        -- Skip whitespace until next non-whitespace
        while self:current() == " " or self:current() == "\t" or self:current() == "\r" or self:current() == "\n" do
          self:advance()
        end
      else
        -- Normal escape sequence
        if next_ch == "b" then
          value = value .. "\b"
        elseif next_ch == "t" then
          value = value .. "\t"
        elseif next_ch == "n" then
          value = value .. "\n"
        elseif next_ch == "f" then
          value = value .. "\f"
        elseif next_ch == "r" then
          value = value .. "\r"
        elseif next_ch == '"' then
          value = value .. '"'
        elseif next_ch == "\\" then
          value = value .. "\\"
        else
          value = value .. next_ch
        end
        self:advance()
      end
    elseif ch == '"' then
      if self:peek() == '"' and self:peek(2) == '"' then
        self:advance() -- Skip first quote
        self:advance() -- Skip second quote
        self:advance() -- Skip third quote
        return self:token("string_ml_basic", value)
      else
        value = value .. ch
        self:advance()
      end
    else
      value = value .. ch
      self:advance()
    end
  end

  return nil -- Unclosed string
end

--- Lex a literal string (single-quoted)
-- @return table|nil Token or nil if not a literal string
function Lexer:lex_string_literal()
  if self:current() ~= "'" then
    return nil
  end

  self:advance() -- Skip opening quote

  -- Check for multi-line string
  if self:current() == "'" and self:peek() == "'" then
    return self:lex_string_ml_literal()
  end

  local value = ""
  while self:current() do
    local ch = self:current()
    if ch == "'" then
      self:advance() -- Skip closing quote
      return self:token("string_literal", value)
    else
      value = value .. ch
      self:advance()
    end
  end

  return nil -- Unclosed string
end

--- Lex a multi-line literal string
-- @return table Multi-line literal string token
function Lexer:lex_string_ml_literal()
  self:advance() -- Skip second quote
  self:advance() -- Skip third quote

  local value = ""

  -- Skip first newline if present
  if self:current() == "\r" or self:current() == "\n" then
    if self:current() == "\r" then
      self:advance()
    end
    if self:current() == "\n" then
      self:advance()
    end
  end

  while self:current() do
    local ch = self:current()
    if ch == "'" then
      if self:peek() == "'" and self:peek(2) == "'" then
        self:advance() -- Skip first quote
        self:advance() -- Skip second quote
        self:advance() -- Skip third quote
        return self:token("string_ml_literal", value)
      else
        value = value .. ch
        self:advance()
      end
    else
      value = value .. ch
      self:advance()
    end
  end

  return nil -- Unclosed string
end

--- Lex a comment
-- @return table|nil Token or nil if not a comment
function Lexer:lex_comment()
  if self:current() ~= "#" then
    return nil
  end

  self:advance() -- Skip #
  local value = ""

  while self:current() and self:current() ~= "\r" and self:current() ~= "\n" do
    value = value .. self:current()
    self:advance()
  end

  -- Trim leading whitespace (space, tab) from comment
  value = value:match("^[ \t]*(.-)$") or value

  return self:token("comment", value)
end

--- Get the next token
-- @return table Next token
function Lexer:next_token()
  -- Return peeked token if available
  if self.peeked_token then
    local token = self.peeked_token
    self.peeked_token = nil
    return token
  end

  -- Skip whitespace
  self:skip_whitespace()

  -- Check for EOF or only newlines remaining (whitespace-only input)
  if self:is_eof() then
    return self:token("eof", nil)
  end

  -- Check if remaining input is only newlines (whitespace-only input)
  local ch = self:current()
  if ch == "\r" or ch == "\n" then
    -- Peek ahead to see if there's any actual content
    local has_content = false
    local temp_pos = self.pos
    while temp_pos <= #self.input do
      local c = self.input:sub(temp_pos, temp_pos)
      if c ~= "\r" and c ~= "\n" and c ~= " " and c ~= "\t" then
        has_content = true
        break
      elseif c == " " or c == "\t" then
        temp_pos = temp_pos + 1
      else
        temp_pos = temp_pos + 1
      end
    end

    if not has_content then
      -- Only whitespace/newlines remaining, skip to EOF
      self.pos = #self.input + 1
      return self:token("eof", nil)
    end
  end

  -- Save token start position
  self.token_line = self.line
  self.token_column = self.column

  -- Check for EOF again after processing
  if self:is_eof() then
    return self:token("eof", nil)
  end

  ch = self:current()

  -- Newline
  if ch == "\r" or ch == "\n" then
    if ch == "\r" then
      self:advance()
    end
    if self:current() == "\n" then
      self:advance()
    end
    return self:token("newline", nil)
  end

  -- Structural characters
  if ch == "=" then
    self:advance()
    return self:token("equal", nil)
  end

  if ch == "," then
    self:advance()
    return self:token("comma", nil)
  end

  if ch == "." then
    self:advance()
    return self:token("dot", nil)
  end

  if ch == "{" then
    self:advance()
    return self:token("brace_left", nil)
  end

  if ch == "}" then
    self:advance()
    return self:token("brace_right", nil)
  end

  if ch == "[" then
    self:advance()
    -- Check for double bracket
    if self:current() == "[" then
      self:advance()
      return self:token("bracket_double_left", nil)
    end
    return self:token("bracket_left", nil)
  end

  if ch == "]" then
    self:advance()
    -- Check for double bracket
    if self:current() == "]" then
      self:advance()
      return self:token("bracket_double_right", nil)
    end
    return self:token("bracket_right", nil)
  end

  -- Comment
  if ch == "#" then
    return self:lex_comment()
  end

  -- Strings
  if ch == '"' then
    return self:lex_string_basic()
  end

  if ch == "'" then
    return self:lex_string_literal()
  end

  -- Sign characters (can start signed numbers)
  if ch == "+" or ch == "-" then
    local token = self:lex_number()
    if token then
      return token
    end
  end

  -- Check for datetime or number (both start with digits)
  if ch:match("[0-9]") then
    -- Try to parse as datetime first
    local token = self:lex_datetime()
    if token then
      return token
    end

    -- Fall back to number parsing
    token = self:lex_number()
    if token then
      return token
    end
  end

  -- Identifiers (includes boolean and special values)
  local token = self:lex_identifier()
  if token then
    return token
  end

  -- Unknown character
  local err = toml_error.ParseError.new(
    string.format("Unexpected character: %s", ch or "EOF"),
    self.line,
    self.column
  )
  error(err)
end

--- Peek at the next token without consuming it
-- @return table Next token
function Lexer:peek_token()
  if not self.peeked_token then
    self.peeked_token = self:next_token()
  end
  return self.peeked_token
end

--- Expect a specific token type
-- @param token_type string Expected token type
-- @return table Token if type matches
-- @raise error if type doesn't match
function Lexer:expect(token_type)
  local token = self:next_token()

  if token.type ~= token_type then
    local err = toml_error.ParseError.new(
      string.format("Expected %s, got %s", token_type, token.type),
      token.line,
      token.column
    )
    error(err)
  end

  return token
end

--- Lex a datetime value
-- @return table|nil Datetime token or nil if not a datetime
function Lexer:lex_datetime()
  local start_col = self.column
  local start_line = self.line
  local start_pos = self.pos

  -- Datetime patterns: YYYY-MM-DDTHH:MM:SS[Z or +/-HH:MM]
  -- Or: YYYY-MM-DDTHH:MM:SS
  -- Or: YYYY-MM-DD
  -- Or: HH:MM:SS[.ffffffff]

  local ch = self:current()

  -- Must start with a digit
  if not ch:match("[0-9]") then
    return nil
  end

  -- Collect the potential datetime value
  -- Datetime can be: YYYY-MM-DDTHH:MM:SS[.ffffffff][Z|±HH:MM]
  -- Or: YYYY-MM-DDTHH:MM:SS[.ffffffff]
  -- Or: YYYY-MM-DD
  -- Or: HH:MM:SS[.ffffffff]
  local value = ""

  -- First, collect while we see datetime characters
  while self:current() and #value < 35 do
    ch = self:current()
    -- Stop at whitespace or other delimiters
    if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" or
       ch == "=" or ch == "," or ch == "]" or ch == "}" or
       ch == "#" then
      break
    end
    value = value .. ch
    self:advance()
  end

  -- Check if it matches datetime patterns
  -- Note: Order matters - more specific patterns first
  local patterns = {
    -- Offset date-time: 1979-05-27T07:32:00.123456Z or 1979-05-27T07:32:00-08:00
    "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+[Z%+%-]%d*:?%d*$",
    "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[Z%+%-]%d*:?%d*$",
    -- Local date-time: 1979-05-27T07:32:00.123456 or 1979-05-27T07:32:00
    "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+$",
    "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$",
    -- Local date: 1979-05-27
    "^%d%d%d%d%-%d%d%-%d%d$",
    -- Local time: 07:32:00.123456 or 07:32:00
    "^%d%d:%d%d:%d%d%.%d+$",
    "^%d%d:%d%d:%d%d$"
  }

  for _, pattern in ipairs(patterns) do
    if value:match(pattern) then
      return self:token("datetime", value)
    end
  end

  -- Not a valid datetime, rewind
  self.pos = start_pos
  self.column = start_col
  self.line = start_line

  return nil
end

-- ============================================================================
-- PARSER MODULE
-- ============================================================================

local Parser = {}
Parser.__index = Parser

--- Create a new parser
-- @param lexer Lexer The lexer to use
-- @return table Parser object
function Parser.new(lexer)
  return setmetatable({
    lexer = lexer,
    current_token = nil,
    cached_token = nil  -- Cached peek token
  }, Parser)
end

--- Get the next token from the lexer
-- @return table Next token
function Parser:next_token()
  if self.cached_token then
    local token = self.cached_token
    self.cached_token = nil
    self.current_token = token
    return token
  end

  local token = self.lexer:next_token()
  self.current_token = token
  return token
end

--- Peek at the next token without consuming it
-- @return table Next token
function Parser:peek_token()
  if not self.cached_token then
    self.cached_token = self.lexer:next_token()
  end
  return self.cached_token
end

--- Expect a specific token type
-- @param token_type string Expected token type
-- @return table Token if type matches
-- @raise error if type doesn't match
function Parser:expect(token_type)
  local token = self:next_token()

  if token.type ~= token_type then
    self:error(string.format("Expected %s, got %s", token_type, token.type))
  end

  return token
end

--- Raise a parse error
-- @param msg string Error message
-- @raise error always
function Parser:error(msg)
  local token = self.current_token or {line = 1, column = 1}
  local err = toml_error.ParseError.new(msg, token.line, token.column)
  error(err)
end

--- Skip newlines and comments
function Parser:skip_newlines_and_comments()
  while true do
    local tok = self:peek_token()
    if tok.type == "newline" or tok.type == "comment" then
      self:next_token()
    else
      break
    end
  end
end

--- Parse a TOML document
-- @return table AST document node
function Parser:parse()
  local doc = ast.document()
  self:skip_newlines_and_comments()

  while self:peek_token().type ~= "eof" do
    self:parse_statement(doc)
    self:skip_newlines_and_comments()
  end

  return doc
end

--- Parse a statement (table header or key-value pair)
-- @param doc table Document node to modify
function Parser:parse_statement(doc)
  local tok = self:peek_token()

  if tok.type == "bracket_left" then
    self:parse_table_header(doc)
  elseif tok.type == "bracket_double_left" then
    self:parse_array_table_header(doc)
  elseif tok.type == "identifier" or tok.type == "string_basic" or tok.type == "string_literal" then
    self:parse_key_value(doc.root.values)
  else
    self:error("Expected table header or key-value pair")
  end
end

--- Parse a key (identifier or string)
-- @return table Key (array of strings for dotted keys)
function Parser:parse_key()
  local key_parts = {}

  while true do
    local token = self:next_token()

    if token.type == "identifier" then
      table.insert(key_parts, token.value)
    elseif token.type == "string_basic" or token.type == "string_literal" then
      table.insert(key_parts, token.value)
    else
      self:error("Expected key")
    end

    -- Check for dotted key
    local next_token = self:peek_token()
    if next_token.type == "dot" then
      self:next_token() -- Consume dot
    else
      break
    end
  end

  return key_parts
end

--- Parse a key-value pair
-- @param current_table table Current table to add key-value to
function Parser:parse_key_value(current_table)
  local key = self:parse_key()
  self:expect("equal")

  local value = self:parse_value()

  -- Handle dotted keys (create nested tables)
  if #key > 1 then
    local current = current_table
    for i = 1, #key - 1 do
      if not current[key[i]] then
        current[key[i]] = ast.inline_table({})
      end
      current = current[key[i]].values
    end
    current[key[#key]] = value
  else
    current_table[key[1]] = value
  end
end

--- Parse a value
-- @return table AST value node
function Parser:parse_value()
  local tok = self:peek_token()

  if tok.type == "string_basic" or tok.type == "string_literal" or
     tok.type == "string_ml_basic" or tok.type == "string_ml_literal" then
    return self:parse_string()
  elseif tok.type == "integer" then
    return self:parse_integer()
  elseif tok.type == "float" then
    return self:parse_float()
  elseif tok.type == "boolean" then
    return self:parse_boolean()
  elseif tok.type == "datetime" then
    return self:parse_datetime()
  elseif tok.type == "brace_left" then
    return self:parse_inline_table()
  elseif tok.type == "bracket_left" then
    return self:parse_array()
  else
    self:error("Expected value")
  end
end

--- Parse a string value
-- @return table AST string node
function Parser:parse_string()
  local token = self:next_token()

  local quote_type = "basic"
  if token.type == "string_literal" then
    quote_type = "literal"
  elseif token.type == "string_ml_basic" then
    quote_type = "ml_basic"
  elseif token.type == "string_ml_literal" then
    quote_type = "ml_literal"
  end

  return ast.string(token.value, quote_type)
end

--- Parse an integer value
-- @return table AST integer node
function Parser:parse_integer()
  local token = self:expect("integer")
  return ast.integer(token.value, "10")
end

--- Parse a float value
-- @return table AST float node
function Parser:parse_float()
  local token = self:expect("float")
  return ast.float(token.value)
end

--- Parse a boolean value
-- @return table AST boolean node
function Parser:parse_boolean()
  local token = self:expect("boolean")
  return ast.boolean(token.value)
end

--- Parse a datetime value
-- @return table AST datetime node
function Parser:parse_datetime()
  local token = self:expect("datetime")
  local dt = datetime.parse(token.value)

  if not dt then
    self:error("Invalid datetime format: " .. token.value)
  end

  return ast.datetime(dt, dt.type)
end

--- Parse an inline table
-- @return table AST inline table node
function Parser:parse_inline_table()
  self:expect("brace_left")
  self:skip_newlines_and_comments()

  local values = {}

  while self:peek_token().type ~= "brace_right" do
    local key = self:parse_key()
    self:expect("equal")
    local value = self:parse_value()
    values[key[1]] = value

    self:skip_newlines_and_comments()

    local next_token = self:peek_token()
    if next_token.type == "comma" then
      self:next_token()
      self:skip_newlines_and_comments()
    end
  end

  self:expect("brace_right")

  return ast.inline_table(values)
end

--- Parse an array
-- @return table AST array node
function Parser:parse_array()
  self:expect("bracket_left")
  self:skip_newlines_and_comments()

  local values = {}

  while self:peek_token().type ~= "bracket_right" do
    local value = self:parse_value()
    table.insert(values, value)

    self:skip_newlines_and_comments()

    local next_token = self:peek_token()
    if next_token.type == "comma" then
      self:next_token()
      self:skip_newlines_and_comments()
    end
  end

  self:expect("bracket_right")

  return ast.array(values)
end

--- Parse a table header [section]
-- @param doc table Document node to modify
function Parser:parse_table_header(doc)
  self:expect("bracket_left")
  local key_parts = self:parse_key()
  self:expect("bracket_right")

  local key = table.concat(key_parts, ".")

  local table_node = ast.table(key)
  doc.tables[key] = table_node

  -- Parse key-value pairs for this table
  self:skip_newlines_and_comments()

  while self:peek_token().type ~= "eof" and
        self:peek_token().type ~= "bracket_left" and
        self:peek_token().type ~= "bracket_double_left" do
    self:parse_key_value(table_node.values)
    self:skip_newlines_and_comments()
  end
end

--- Parse an array of tables header [[section]]
-- @param doc table Document node to modify
function Parser:parse_array_table_header(doc)
  self:expect("bracket_double_left")
  local key_parts = self:parse_key()
  self:expect("bracket_double_right")

  local key = table.concat(key_parts, ".")

  -- Create array table if it doesn't exist
  if not doc.tables[key] then
    doc.tables[key] = ast.table(key)
    doc.tables[key].is_array = true
    doc.tables[key].array_items = {}
  end

  local table_node = ast.table(key)
  table_node.is_array = true
  table.insert(doc.tables[key].array_items, table_node)

  -- Parse key-value pairs for this array item
  self:skip_newlines_and_comments()

  while self:peek_token().type ~= "eof" and
        self:peek_token().type ~= "bracket_left" and
        self:peek_token().type ~= "bracket_double_left" do
    self:parse_key_value(table_node.values)
    self:skip_newlines_and_comments()
  end
end

-- ============================================================================
-- SERIALIZER MODULE
-- ============================================================================

local serializer = {}

--- Default options
local DEFAULT_OPTIONS = {
  indent = 2,
  sort_keys = false,
  inline_max_keys = 3,
  use_table_headers = false,
  array_huge_threshold = 5,
  use_array_table_format = true  -- Use [[array]] format for arrays of tables
}

--- Check if a table is an array (sequential integer keys)
-- @param tbl table Table to check
-- @return boolean True if array
local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end

  local count = 0
  for k, v in pairs(tbl) do
    if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
      return false
    end
    count = count + 1
  end

  return count > 0
end

--- Escape a string for TOML basic string
-- @param str string String to escape
-- @return string Escaped string
local function escape_string(str)
  -- Escape special characters
  local escaped = str:gsub("\\", "\\\\")
                  :gsub('"', '\\"')
                  :gsub("\b", "\\b")
                  :gsub("\f", "\\f")
                  :gsub("\n", "\\n")
                  :gsub("\r", "\\r")
                  :gsub("\t", "\\t")

  return escaped
end

--- Serialize a value to TOML format
-- @param value any Value to serialize
-- @param table options Serializer options
-- @return string TOML representation
function serializer.serialize_value(value, options)
  local value_type = type(value)

  if value_type == "string" then
    -- Check if we can use literal string (no escape needed)
    if value:match("^[%w%s%-_%./]+$") and not value:match("[\']") then
      return '"' .. escape_string(value) .. '"'
    else
      return '"' .. escape_string(value) .. '"'
    end
  elseif value_type == "number" then
    -- Check if integer or float
    if math.floor(value) == value then
      return tostring(math.floor(value))
    else
      -- Handle special float values
      if value == math.huge then
        return "inf"
      elseif value == -math.huge then
        return "-inf"
      elseif value ~= value then
        return "nan"
      end
      return tostring(value)
    end
  elseif value_type == "boolean" then
    return tostring(value)
  elseif value_type == "table" then
    -- Check if it's a datetime table
    if value.type and (value.type == "datetime_offset" or
                       value.type == "datetime_local" or
                       value.type == "date_local" or
                       value.type == "time_local") then
      local serialized = datetime.serialize(value)
      if serialized then
        return serialized
      else
        error("Failed to serialize datetime")
      end
    elseif is_array(value) then
      local elements = {}
      for _, v in ipairs(value) do
        table.insert(elements, serializer.serialize_value(v, options))
      end
      return "[" .. table.concat(elements, ", ") .. "]"
    else
      -- Inline table
      local kv_pairs = {}
      for k, v in pairs(value) do
        if type(k) == "string" then
          table.insert(kv_pairs, k .. " = " .. serializer.serialize_value(v, options))
        end
      end
      return "{" .. table.concat(kv_pairs, ", ") .. "}"
    end
  else
    error("Cannot serialize type: " .. value_type)
  end
end

--- Check if a table should be inline
-- @param tbl table Table to check
-- @param options table Serializer options
-- @return boolean True if should be inline
local function should_be_inline(tbl, options)
  local count = 0
  for k, v in pairs(tbl) do
    count = count + 1
    if count > options.inline_max_keys then
      return false
    end
  end

  -- Check if all values are simple (non-table)
  for k, v in pairs(tbl) do
    if type(v) == "table" and not is_array(v) then
      return false
    end
  end

  return true
end

--- Get sorted keys from a table
-- @param tbl table Table to get keys from
-- @return table Sorted keys
local function get_sorted_keys(tbl)
  local keys = {}
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      table.insert(keys, k)
    end
  end
  table.sort(keys)
  return keys
end

--- Serialize a table to TOML format
-- @param data table Data to serialize
-- @param options table Serializer options
-- @param string prefix Key prefix for nested tables
-- @param number indent_level Current indentation level
-- @return string TOML representation
function serializer.encode(data, options, prefix, indent_level)
  options = options or {}
  for k, v in pairs(DEFAULT_OPTIONS) do
    if options[k] == nil then
      options[k] = v
    end
  end

  -- When using array table format, prefer dotted keys over inline tables
  if options.use_array_table_format then
    options.inline_max_keys = 1
  end

  prefix = prefix or ""
  indent_level = indent_level or 0

  local lines = {}
  local indent_str = string.rep(" ", indent_level * options.indent)

  if type(data) ~= "table" then
    return indent_str .. serializer.serialize_value(data, options)
  end

  -- Get keys to process
  local keys
  if options.sort_keys then
    keys = get_sorted_keys(data)
  else
    keys = {}
    for k, v in pairs(data) do
      if type(k) == "string" then
        table.insert(keys, k)
      end
    end
  end

  -- Separate simple values, arrays, and tables
  local simple_values = {}
  local arrays = {}
  local nested_tables = {}

  for _, key in ipairs(keys) do
    local value = data[key]
    local value_type = type(value)

    if value_type == "table" then
      if is_array(value) then
        arrays[key] = value
      else
        nested_tables[key] = value
      end
    else
      simple_values[key] = value
    end
  end

  -- Serialize simple values first (to maintain order like original file)
  for key, value in pairs(simple_values) do
    local full_key = prefix ~= "" and prefix .. "." .. key or key
    local serialized = serializer.serialize_value(value, options)
    table.insert(lines, indent_str .. full_key .. " = " .. serialized)
  end

  -- Serialize nested tables (before arrays when use_array_table_format is true)
  for key, value in pairs(nested_tables) do
    local full_key = prefix ~= "" and prefix .. "." .. key or key

    -- Check if it's a datetime table - serialize inline as single value
    if value.type and (value.type == "datetime_offset" or
                       value.type == "datetime_local" or
                       value.type == "date_local" or
                       value.type == "time_local") then
      local serialized = datetime.serialize(value)
      if serialized then
        table.insert(lines, indent_str .. full_key .. " = " .. serialized)
      else
        error("Failed to serialize datetime: " .. full_key)
      end
    elseif options.use_table_headers then
      -- Use table header syntax
      table.insert(lines, "")
      table.insert(lines, indent_str .. "[" .. full_key .. "]")

      -- Get nested table content
      local nested_lines = {}
      local nested_keys = options.sort_keys and get_sorted_keys(value) or {}
      if #nested_keys == 0 then
        for k, v in pairs(value) do
          if type(k) == "string" then
            table.insert(nested_keys, k)
          end
        end
      end

      for _, nested_key in ipairs(nested_keys) do
        local nested_value = value[nested_key]
        if type(nested_value) ~= "table" or (type(nested_value) == "table" and should_be_inline(nested_value, options)) then
          local serialized = serializer.serialize_value(nested_value, options)
          table.insert(nested_lines, indent_str .. string.rep(" ", options.indent) .. nested_key .. " = " .. serialized)
        end
      end

      for _, line in ipairs(nested_lines) do
        table.insert(lines, line)
      end
    elseif should_be_inline(value, options) then
      -- Inline table
      local full_key = prefix ~= "" and prefix .. "." .. key or key
      local serialized = serializer.serialize_value(value, options)
      table.insert(lines, indent_str .. full_key .. " = " .. serialized)
    else
      -- Recursive nested table (dotted keys)
      local nested_result = serializer.encode(value, options, full_key, indent_level)
      for line in nested_result:gmatch("[^\r\n]+") do
        if line ~= "" then
          table.insert(lines, line)
        end
      end
    end
  end

  -- Serialize arrays last
  for key, value in pairs(arrays) do
    local full_key = prefix ~= "" and prefix .. "." .. key or key

    -- Check if this is an array of tables and we should use array table format
    local use_array_table = options.use_array_table_format and
                           #value > 0 and
                           type(value[1]) == "table"

    if use_array_table then
      -- Use [[arrayname]] format for each element
      for idx, element in ipairs(value) do
        -- Add blank line before first element only if there's already content
        if idx == 1 and #lines > 0 then
          table.insert(lines, "")
        end

        table.insert(lines, indent_str .. "[[" .. full_key .. "]]")

        -- Serialize each field in the element
        if type(element) == "table" then
          local elem_keys = options.sort_keys and get_sorted_keys(element) or {}
          if #elem_keys == 0 then
            for k in pairs(element) do
              table.insert(elem_keys, k)
            end
          end

          for _, elem_key in ipairs(elem_keys) do
            if type(element[elem_key]) ~= "table" then
              local serialized = serializer.serialize_value(element[elem_key], options)
              table.insert(lines, indent_str .. string.rep(" ", options.indent) .. elem_key .. " = " .. serialized)
            end
          end
        else
          -- Primitive value in array
          local serialized = serializer.serialize_value(element, options)
          table.insert(lines, indent_str .. string.rep(" ", options.indent) .. full_key .. " = " .. serialized)
        end
      end

      -- Add blank line after array table section to separate from other content
      table.insert(lines, "")
    else
      -- Use inline array format
      local serialized = serializer.serialize_value(value, options)
      table.insert(lines, indent_str .. full_key .. " = " .. serialized)
    end
  end

  local result = table.concat(lines, "\n")
  -- Ensure file ends with newline
  if result ~= "" then
    result = result .. "\n"
  end
  return result
end

--- Encode Lua table to TOML string (convenience wrapper)
-- @param data table Lua data
-- @param table options Serializer options
-- @return string TOML string
function serializer.encode_to_string(data, options)
  return serializer.encode(data, options)
end

-- ============================================================================
-- MAIN TOML MODULE
-- ============================================================================

local toml = {}

--- Parse TOML string into Lua table
-- @param input string TOML document
-- @return table|nil parsed_data Parsed TOML as nested Lua tables
-- @return string|nil error_msg Error message if parsing failed
function toml.parse(input)
  if type(input) ~= "string" then
    return nil, "Input must be a string"
  end

  local ok, result = pcall(function()
    local lexer = Lexer.new(input)
    local parser = Parser.new(lexer)
    local ast_doc = parser:parse()
    return toml.ast_to_table(ast_doc)
  end)

  if not ok then
    local err_msg = toml_error.to_string(result)
    return nil, err_msg
  end

  return result
end

--- Parse TOML file
-- @param path string File path
-- @return table|nil parsed_data Parsed TOML as nested Lua tables
-- @return string|nil error_msg Error message if parsing failed
function toml.parse_file(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, "Cannot open file: " .. err
  end

  local content = file:read("*all")
  file:close()

  return toml.parse(content)
end

--- Convert AST node to Lua table
-- @param node table AST node
-- @return table Lua table representation
function toml.ast_to_table(node)
  if not node then
    return {}
  end

  local node_type = node.type

  if node_type == "Document" then
    local result = toml.ast_to_table(node.root)
    -- Merge all tables into result
    for key, tbl_node in pairs(node.tables) do
      if tbl_node.is_array then
        result[key] = {}
        for _, item in ipairs(tbl_node.array_items) do
          table.insert(result[key], toml.ast_to_table(item))
        end
      else
        result[key] = toml.ast_to_table(tbl_node)
      end
    end
    return result
  end

  if node_type == "Table" then
    local result = {}
    for key, value_node in pairs(node.values) do
      result[key] = toml.ast_to_table(value_node)
    end
    return result
  end

  if node_type == "InlineTable" then
    local result = {}
    for key, value_node in pairs(node.values) do
      result[key] = toml.ast_to_table(value_node)
    end
    return result
  end

  if node_type == "Array" then
    local result = {}
    for _, value_node in ipairs(node.values) do
      table.insert(result, toml.ast_to_table(value_node))
    end
    return result
  end

  if node_type == "String" then
    return node.value
  end

  if node_type == "Integer" then
    return node.value
  end

  if node_type == "Float" then
    return node.value
  end

  if node_type == "Boolean" then
    return node.value
  end

  if node_type == "DateTime" then
    return node.value
  end

  -- Unknown node type
  return nil
end

--- Encode Lua table to TOML string
-- @param data table Lua data
-- @param table options Serializer options (indent, sort_keys, etc.)
-- @return string toml_string
function toml.encode(data, options)
  if type(data) ~= "table" then
    error("Data must be a table")
  end

  return serializer.encode(data, options)
end

--- Encode Lua table to TOML file
-- @param data table Lua data
-- @param path string Output path
-- @param table options Serializer options
-- @return boolean success
-- @return string|nil error_msg
function toml.encode_file(data, path, options)
  if type(data) ~= "table" then
    return false, "Data must be a table"
  end

  if type(path) ~= "string" then
    return false, "Path must be a string"
  end

  local toml_string
  local ok, err = pcall(function()
    toml_string = toml.encode(data, options)
  end)

  if not ok then
    return false, "Encoding failed: " .. tostring(err)
  end

  local file, err = io.open(path, "w")
  if not file then
    return false, "Cannot open file for writing: " .. err
  end

  file:write(toml_string)
  file:close()

  return true
end

--- Validate parsed data structure
-- @param data table Parsed TOML data
-- @return boolean valid
-- @return string|nil error_msg
function toml.validate(data)
  -- Basic validation: check if it's a table
  if type(data) ~= "table" then
    return false, "Data must be a table"
  end

  return true
end

return toml
