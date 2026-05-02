---
-- Debug Utilities Module
--
-- This module provides debugging utilities for applications,
-- including buffer packing for diagnostic purposes.
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local sysinfo = require 'utils.sysinfo'
local class = require 'middleclass'
local app_logger = require 'app.logger'

---
-- Debug Utilities Class
--
-- Provides methods for collecting and saving application
-- debug information including communication logs and system logs.
---
local debug = class("APP_LIB_DEBUG")

---
-- Initialize debug utilities instance
-- @param app_name: application name
-- @param logger: optional logger instance (creates default if nil)
---
function debug:initialize(app_name, logger)
	self._app_name = app_name
	self._logger = logger or app_logger:new(app_name)
end

---
-- Pack all application communication and log data into a file
-- Queries buffer service for app-specific data and saves to JSON file
-- @return: filename on success, nil and error message on failure
---
function debug:pack_all()
	local buffer, err = snax.queryservice('buffer')
	if not buffer then
		return nil, err
	end
	local comms = buffer.req.get_comm(self._app_name) or {}
	local logs = buffer.req.get_log(self._app_name) or {}

	local dir = sysinfo.data_dir()..'/freeioe_buffer_pack'
	lfs.mkdir(dir)
	local fn = string.format('%s/%s.%d.pack', dir, self._app_name, os.time())
	local f, err = io.open(fn, 'w+')
	if not f then
		return nil, err
	end

	local data, err = cjson.encode({
		comm = comms,
		log = logs
	})
	if not data then
		return nil, err
	end

	f:write(data)
	f:close()

	return fn
end

return debug
