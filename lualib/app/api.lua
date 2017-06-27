local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'

local api = class("APP_MGR_API")

function api:initialize(app_name, mgr_snax)
end

function api:get_prop_value(device, prop, type)
end

function api:set_prop_value(device, prop, type, value)
end

return api
