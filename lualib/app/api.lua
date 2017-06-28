local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'

local api = class("APP_MGR_API")

function api:initialize(app_name, mgr_snax)
end

--[[
-- Set devices update callback
-- @param app: default is "*"
--]]
function api:set_device_cb(app, func)
end

--[[
-- List devices
-- @param app: default is "*"
--]]
function api:list_devices(app)
end

function api:add_device(sn, props)
end

function api:del_device(sn)
end

function api:get_device(sn)
end

function api:set_prop_cb(sn, func)
end

function api:get_prop_value(sn, prop, type)
end

function api:set_prop_value(sn, prop, type, value)
end

--[[
-- generate device serial number
--]]
function api:gen_sn()
end

--[[
-- Get device configuration string by device serial number(sn)
--]]
function api:get_conf(sn)
end

--[[
-- Set device configuration string
--]]
function api:set_conf(sn, conf)
end

return api
