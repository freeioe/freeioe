local restful = require 'http.restful'
local class = require 'middleclass'

local client = class('db.siridb.http')

local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 9020

	return string.format('%s://%s:%d', proto, host, port)
end

function client:initialize(options)
	self._options = options
	local host = option_to_url(self._options)
	local auth = {options.username or 'sa', options.password or 'siri'}
	self._rest = restful:new(host, self._options.timeout, nil, auth)
end

function client:post(url, params, data)
	return self._rest:post(url, params, data)
end

function client:get(url, params, data)
	return self._rest:get(url, params, data)
end

function client:new_database(dbname, time_precision, buffer_size, duration_num, duration_log)
	assert(dbname)
	local data = {
		dbname = dbname,
		time_precision = time_precision or 'ms',
		buffer_size = tonumber(buffer_size) or 1024,
		duration_num = duration_num or '52w',
		duration_log = duration_log or '1w'
	}
	return self:post('/new-database', nil, data)
end

function client:new_account(user, passwd)
	assert(user, "User missing")
	assert(passwd, "Password missing")
	return self:post('/new-account', nil, {
		account = user,
		password = passwd
	})
end

function client:change_password(user, password)
	assert(user, "User missing")
	assert(passwd, "Password missing")
	return self:post('/change-password', nil, {
		account = user,
		password = passwd
	})
end

function client:drop_account(user)
	assert(user, "User missing")
	return self:post('/drop-account', nil, {
		account = user
	})
end

function client:new_pool(dbname, user, passwd, host, port)
	assert(dbname, 'dbname missing')
	return self:post('/new-pool', nil, {
		dbname = dbname,
		username = user,
		password = passwd,
		host = host,
		port = port
	})
end

function client:new_replica(dbname, user, passwd, host, port, pool)
	assert(dbname, 'dbname missing')
	return self:post('/new-pool', nil, {
		dbname = dbname,
		username = user,
		password = passwd,
		host = host,
		port = port,
		pool = pool
	})
end

function client:drop_database(dbname, ignore_offline)
	assert(dbname, "dbname missing")
	return self:post('/drop-account', nil, {
		database = dbname,
		ignore_offline = ignore_offline and true or false
	})
end

function client:get_version()
	return self:get('/get-version')
end

function client:get_accounts()
	return self:get('/get-accounts')
end

function client:get_databases()
	return self:get('/get-databases')
end

return client
