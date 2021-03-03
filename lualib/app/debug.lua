local skynet = require 'skynet'
local snax = require 'skynet.snax'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local sysinfo = require 'utils.sysinfo'
local class = require 'middleclass'
local app_logger = require 'app.logger'

local debug = class("APP_LIB_DEBUG")

function debug:initialize(app_name, logger)
	self._app_name = app_name
	self._logger = logger or app_logger:new(app_name)
end

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
