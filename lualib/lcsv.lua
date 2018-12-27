-- lcsv | Lua CSV Parsing
-- By daelvn
-- 10.09.2018

local lcsv = {}

-- Source handling
function lcsv.open (file, mode)
  local handle = io.open (file, mode or "r+")
  getmetatable (handle).filename = file
  return handle
end

-- Parsing
local function mapLineToHeader (csvl, header)
  if not header then return csvl end
  local result = {}
  for i=1, #header do result [header [i]] = csvl [i] end
  return result
end
local function mapHeaderToLine (csvl, header)
  if not header then return csvl end
  local result = {}
  for i=1, #header do result [i] = csvl [header [i]] end
  return result
end
local function toLines (str)
  local lines = {}
   local function helper (line)
      table.insert (lines, line)
      return ""
   end
   helper ((str:gsub ("(.-)\r?\n", helper)))
   for i,v in ipairs (lines) do if v == "\n" then lines [i] = nil end end
   return lines
end
lcsv.mapLineToHeader = mapLineToHeader
lcsv.mapHeaderToLine = mapHeaderToLine
lcsv.toLines         = toLines
-- luacheck: ignore a
function lcsv.parseLine (str, header)
  -- Thanks to LuaUsers
  str = str .. ','        -- ending comma
  local t = {}        -- table to collect fields
  local fieldstart = 1
  repeat
    -- next field is quoted? (start with `"'?)
    if string.find(str, '^"', fieldstart) then
      local a, c
      local i  = fieldstart
      repeat
        -- find closing quote
        a, i, c = string.find(str, '"("?)', i+1)
      until c ~= '"'    -- quote not followed by quote?
      if not i then error('unmatched "') end
      local f = string.sub(str, fieldstart+1, i-1)
      table.insert(t, (string.gsub(f, '""', '"')))
      fieldstart = string.find(str, ',', i) + 1
    else                -- unquoted; find next comma
      local nexti = string.find(str, ',', fieldstart)
      table.insert(t, string.sub(str, fieldstart, nexti-1))
      fieldstart = nexti + 1
    end
  until fieldstart > string.len(str)
  return header and mapLineToHeader (t, header) or t
end
function lcsv.parseAll (lines, hasHeader)
  local result  = {}
  -- Header
  local header
  local i      = 1
  if hasHeader then
    header = lcsv.parseLine (lines [1])
    i      = 2
  end
  -- All lines
  while lines [i] do
    table.insert (result,
      mapLineToHeader (lcsv.parseLine (lines [i]), header)
    )
    i = i + 1
  end
  --
  return result, header
end

-- Reading
function lcsv.readHeader (csvh, move)
  local cur = csvh:seek "cur"
  csvh:seek "set"
  local header = lcsv.parseLine (csvh:read "*l")
  if move then csvh:seek ("set", cur) end
  return header
end
function lcsv.readLine (csvh, header)
  local line = csvh:read "*l"
  return lcsv.parseLine (line, header)
end
function lcsv.readAll (csvh, hasHeader)
  local lines = toLines (csvh:read "*a")
  return lcsv.parseAll (lines, hasHeader)
end

-- Escaping
function lcsv.escape (str)
  if str:find '[,"]' then return '"' .. str:gsub ('"', '""') .. '"' else return str end
end

-- To CSV
function lcsv.newCsvLine (...)
  local result = ""
  for _,str in ipairs {...} do
    result = result .. "," .. lcsv.escape (tostring (str))
  end
  return result:sub (2)
end
function lcsv.newCsv (t)
  local result = ""
  for _,line in ipairs (t) do
    result = result .. lcsv.newCsvLine (table.unpack (line)) .. "\n"
  end
  result = result:gsub ("\n$", "")
  return result
end
function lcsv.toCsvLine (csvl, header)
  local result = ""
  if header then csvl = mapHeaderToLine (csvl, header) end
  for _,field in ipairs (csvl) do
    result = result .. "," .. lcsv.escape (tostring (field))
  end
  return result:sub (2)
end
function lcsv.toCsv (csvt, header)
  local result = ""
  for _,line in ipairs (csvt) do
    if header then line = mapHeaderToLine (line, header) end
    result = result .. lcsv.toCsvLine (line) .. "\n"
  end
  return result
end

-- Writing
function lcsv.writeRawLine (csvh, ...)
  csvh:write (lcsv.newCsvLine (...) .. "\n")
end
function lcsv.writeLine (csvh, csvl, header)
  csvh:write (lcsv.toCsvLine (csvl, header) .. "\n")
end
function lcsv.writeRawAll (csvh, t)
  csvh:write (lcsv.newCsv (t) .. "\n")
end
function lcsv.writeAll (csvh, csvt, header)
  csvh:write (lcsv.toCsv (csvt, header) .. "\n")
end

-- Return
return lcsv
