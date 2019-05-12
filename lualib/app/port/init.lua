local agent_serial = require 'app.port.agent_serial'
local agent_socket = require 'app.port.agent_socket'
local timeout_channel = require 'app.port.timeout_channel'
local helper = require 'app.port.helper'

local _M = {}

---
-- Create serial port
-- @tparam opt Option data table
-- @tparam shared_name Shared name string, used for share this serial port between application [instance]
function _M.new_agent_serial(opt, shared_name)
	return agent_serial:new(opt, shared_name)
end

---
-- Create socket port
-- @tparam opt Option data table
-- @tparam shared_name Shared name string, used for share this socket port between application [instance]
function _M.new_agent_socket(opt, shared_name)
	return agent_socket:new(opt, shared_name)
end

function _M.new_serial(conf, name)
	return timeout_channel('serialchannel', conf, name)
end

function _M.new_socket(conf, name)
	return timeout_channel('socketchannel', conf, name)
end


_M.helper = helper

return _M
