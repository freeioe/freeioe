local class = require 'middleclass'
local cjson = require 'cjson.safe'
local restful = require 'http.restful'

local database = class('db.victoria.database')

local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 8428

	return string.format('%s://%s:%d', proto, host, port)
end

function database:initialize(options)
	self._options = assert(options)
	local host = option_to_url(options)
	local auth = options.username and {options.username, options.password} or nil
	self._rest = restful:new(host, self._options.timeout, nil, auth)
end

function database:export(match, start, etime, max_rows_per_line)
	local sts, body = self._rest:post('/api/v1/export', {
		match = match,
		start = start,
		['end'] = etime,
		max_rows_per_line = max_rows_per_line
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body)
end

return database
