
local _M  = {}

local html_escape_entities = {
	['&'] = '&amp;',
	['<'] = '&lt;',
	['>'] = '&gt;',
	['"'] = '&quot;',
	["'"] = '&#039;'
}

function _M.escape(text)
	text = text or ""
	return (text:gsub([=[["><'&]]=], html_escape_entities))
end

function _M.encode_query_string (t, sep)
	local escape = _M.escape
	local sep = sep or "&"
	local i = 0
	local buf = { }
	for k, v in pairs(t) do
		if type(k) == "number" and type(v) == "table" then
			k, v = v[1], v[2]
		end
		buf[i + 1] = escape(k)
		buf[i + 2] = "="
		buf[i + 3] = escape(tostring(v))
		buf[i + 4] = sep
		i = i + 4
	end
	buf[i] = nil
	return table.concat(buf)
end

return _M
