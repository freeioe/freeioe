local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local log = require 'utils.log'
local app_api = require 'app.api'

local api = nil
local buf_list = {}
local max_buf_size = 256

--[[
-- Api Handler
--]]
local comm_buffer = nil
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		local hex = crypt.hexencode(table.concat({...}, '\t'))
		hex = string.gsub(hex, "%w%w", "%1 ")
		local list  = buf_list[app] or {}
		list[#list + 1] = {
			sn = sn,
			dir = dir,
			ts = ts,
			data = hex
		}
		if #list > 256 then
			table.remove(list, 1)
		end
		buf_list[app] = list
	end,
}

function response.ping()
	return "PONG"
end

function response.get(app)
	if not app then
		return buf_list
	end
	return buf_list[app]
end

function init()
	log.notice("COMM data buffer service started!")

	skynet.fork(function()
		api = app_api:new('__COMM_DATA_LOGGER')
		api:set_handler(Handler, false)
	end)
end

function exit(...)
end
