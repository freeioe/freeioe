local app_serial = require 'app.serial'
local app_socket = require 'app.socket'
local helper = require 'app.port_helper'

local _M = {}

---
-- Create serial port
-- @tparam opt Option data table
-- @tparam shared_name Shared name string, used for share this serial port between application [instance]
function _M.new_serial(opt, shared_name)
	return app_serial:new(opt)
end

---
-- Create socket port
-- @tparam opt Option data table
-- @tparam shared_name Shared name string, used for share this socket port between application [instance]
function _M.new_socket(opt, shared_name)
	return app_socket:new(opt)
end

_M.helper = helper

return _M
