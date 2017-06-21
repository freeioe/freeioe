local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'

local app = nil
local app_name = "UNKNOWN"

local on_close = function()
	app_name = "UNKNOWN"
	app = nil
end

function response.ping()
	return "Pong "..app_name
end

function response.start(...)
	local r, m = pcall(require, app_name..".app")
	if not r then
		return nil, m
	end
	app = m:new(app_name)

	return app
end

function response.stop(reason)
	if app then
		app:close()
	end
	on_close()
end

function init(name)
	app_name = name
	log.debug("App "..app_name.." starting")
end

function exit()
	log.debug("App "..app_name.." closed.")
	on_close()
end
