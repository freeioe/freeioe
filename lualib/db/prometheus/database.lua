local class = require 'middleclass'
local cjson = require 'cjson.safe'
local sdata = require 'db.prometheus.data'
local restful = require 'http.restful'

local database = class('db.prometheus.database')

local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 9020

	return string.format('%s://%s:%d', proto, host, port)
end

function database:initialize(options)
	self._options = assert(options)
	local host = option_to_url(options)
	local auth = options.username and {options.username, options.password} or nil
	self._rest = restful:new(host, self._options.timeout, nil, auth)

	local url = self._options.url or '/metric'
	if options.job then
		url = url .. '/job/' .. options.job
	end
	if options.instance then
		url = url ..'/instance/' .. options.instance
	end
	self._url = url
end

function database:insert(data, auto_clean)
	local sts, body = self._rest:post(self._url, nil, data:encode(auto_clean))
	if tonumber(sts) == 204 then
		return true
	end
	return nil, tostring(body)
end

function database:insert_metric(metric, auto_clean)
	local data = sdata:new()
	data:add_metric(metric)
	return self:insert(data, auto_clean)
end

-- time is <rfc3339> or <unix timestamp>
-- timeout = <duration>
function database:query(query, time, timeout)
	local sts, body = self._rest:post('/api/v1/query', {
		query = query,
		time = time,
		timeout = timeout
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

-- start, etime is <rfc3339> or <unix timestamp>
-- step = <duration | float>
-- timeout = <duration>
function database:query_range(query, start, etime, step, timeout)
	local sts, body = self._rest:post('/api/v1/query_range', {
		query = query,
		start = start,
		['end'] = etime,
		step = step,
		timeout = timeout
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

function database:query_series(match, start, etime)
	local sts, body = self._rest:post('/api/v1/series', {
		match = match,
		start = start,
		['end'] = etime
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

function database:query_labels(match, start, etime)
	local sts, body = self._rest:post('/api/v1/labels', {
		match = match,
		start = start,
		['end'] = etime
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

return database
