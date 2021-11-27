local qpack = require 'qpack.safe'
local class = require 'middleclass'
local restful = require 'http.restful'
local sdata = require 'db.siridb.data'

local database = class('db.siridb.database')

local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 9020

	return string.format('%s://%s:%d', proto, host, port)
end

function database:initialize(options, dbname)
	self._options = assert(options)
	local host = option_to_url(self._options)
	local auth = {options.username or 'iris', options.password or 'siri'}
	self._rest = restful:new(host, self._options.timeout, nil, auth)
	self._ts = options.time_precision or 'ms'
	self._db = dbname or options.db or 'test'
end

function database:time_precision()
	return self._ts
end

function database:dbname()
	return self._db
end

function database:options()
end

function database:post(url, params, data)
	local body = nil
	if data then
		local str, err = qpack.encode(data)
		if not str then
			return nil, err
		end
		body = str
	end

	return self._rest:post(url, params, body, 'application/qpack')
end

function database:get(url, params, data)
	local body = nil
	if data then
		local str, err = qpack.encode(data)
		if not str then
			return nil, err
		end
		body = str
	end
	return self._rest:get(url, params, body, 'application/qpack')
end

function database:insert(data, auto_clean)
	assert(data, "data missing")
	assert(data.encode, "data object incorrect")
	local status, body = self:post('/insert/'..self._db, nil, data:encode(self._ts, auto_clean))
	if status == 200 then
		return true
	else
		return nil, tostring(body)
	end
end

function database:insert_series(series, auto_clean)
	assert(series, "series missing")
	local data = sdata:new()
	data:add_series(series:series_name(), series)
	return self:insert(data, auto_clean)
end

--- Query between .. and .. could using ms timestamp, and the data returns includes
--		sample on start, but not sample on end. So increase 1ms to includes the data your want
--		it means the data returns [start, end)
function database:query(query, time_precision)
	assert(query, "query string missing")
	local status, body = self:post('/query/'..self._db, nil, {
		q = query,
		t = time_precision or self._ts
	})
	if status == 200 then
		local data, err = qpack.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body), status
end

function database:exec(sql)
	assert(sql, "query string missing")
	local status, body = self:post('/query/'..self._db, nil, {q = sql})
	if status == 200 then
		local data, err = qpack.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body), status
end

return database
