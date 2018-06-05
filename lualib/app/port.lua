local app_serial = require 'app.serial'
local app_socket = require 'app.socket'
local helper = require 'app.port_helper'

local _M = {}

function _M.new_serial(opt, shared_name)
	return app_serial:new(opt)
end

function _M.new_socket(opt, shared_name)
	return app_socket:new(opt)
end

_M.helper = helper

return _M
