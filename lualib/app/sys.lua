local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local coroutine = require 'skynet.coroutine'
local class = require 'middleclass'
local ioe = require 'ioe'
local api = require 'app.api'
local logger = require 'app.logger'
local conf_api = require 'app.conf.api'
local lfs = require 'lfs'
local cancelable_timeout = require 'cancelable_timeout'

local sys = class("APP_MGR_SYS")
sys.API_VER = 15 -- 2023.11.1 :: added app_name method in device object
sys.API_MIN_VER = 1

---
-- Write log with level
-- @tparam level string Log level string (error, info, notice, debug, trace)
function sys:log(level, ...)
	return self._logger:log(level, ...)
end

---
-- Get logger interface object
-- @treturn logger object
function sys:logger()
	return self._logger
end

---
-- Dump communication stream data
-- @tparam sn string Device serial number
-- @tparam dir string Direction description
-- @treturn nil
function sys:dump_comm(sn, dir, ...)
	local sn = sn or self:app_sn()
	return self._data_api:_dump_comm(sn, dir, ...)
end

---
-- Fire application event
-- @tparam sn string Device serial number
-- @tparam level number Event level (refer to app.event module's LEVELS)
-- @tparam type_ number Event type (refere to app.event module's EVENTS)
-- @tparam info string Event information
-- @tparam data table Event data table object
-- @tparam timestamp number Event occur timestamp (or iot.time())
function sys:fire_event(sn, level, type_, info, data, timestamp)
	return self._data_api:_fire_event(sn or self:app_sn(), level, type_, info, data or {}, timestamp or ioe.time())
end

---
-- Fork a new coroutine to run a function
-- @tparam func function Excution function
-- @tparam ... args
function sys:fork(func, ...)
	skynet.fork(func, ...)
end

---
-- Set an timeout function execution
-- @tparam ms number Time in milli-seconds
-- @tparam func function Execution function
function sys:timeout(ms, func)
	return skynet.timeout(ms / 10, func)
end

---
-- Create can cancelable timeout function execution
-- @tparam ms number Time in milli-seconds
-- @tparam func function Execution function
-- @treturn function An cancel function holder
function sys:cancelable_timeout(ms, func)
	local cancel = cancelable_timeout(ms / 10, func)
	return cancel
end

---
-- Quit current application process
--   this won't save 
function sys:exit()
	skynet.exit()
end

---
-- Abort FreeIOE application in five seconds
function sys:abort()
	self._logger:warning("FreeIOE will be closed after 5 seconds!")
	ioe.abort(5000)
end

---
-- Get FreeIOE uptime in ms
-- @treturn number ms
function sys:now()
	return skynet.now() * 10
end

---
-- Try to fix FreeIOE time issue (caused by NTP)
function sys:fix_time()
	if skynet.fix_time then
		local r = skynet.fix_time()
		--- previous fix_time does not returns any value, so r will be nil
		if r or r == nil then
			return
		end
	end

	self._logger:warning("Reboot FreeIOE to fix time diff issue!")
	self:abort()
end

---
-- Get current time seconds (UTC now)
-- @treturn number refer to ioe.time()
function sys:time()
	return ioe.time()
end

---
-- Get FreeIOE start time (in UTC, seconds)
-- @treturn number refer to ioe.starttime()
function sys:start_time()
	return ioe.starttime()
end

---
-- Yield current coroutine
function sys:yield()
	return skynet.yield()
end

---
-- Sleep current coroutine, let others run
-- @tparam ms number Sleep time in ms
-- @tparam token The token can be used to abort sleep
function sys:sleep(ms, token)
	local ts = math.floor(ms / 10)
	return skynet.sleep(ts, token)
end

---
-- Get data access api
-- @treturn object refer to app.api
function sys:data_api()
	return self._data_api
end

---
-- Get debug api(not implemented)
function sys:debug_api()
	if self._debug_api then
		self._debug_api = debug:new(app_name, self._logger)
	end
	return  self._debug_api
end

---
-- Get current coroutine object
function sys:self_co()
	return coroutine.running()
end

---
-- Wait for be wakeup by token
-- @tparam any The token used to wakeup this wait
function sys:wait(token)
	return skynet.wait(token)
end

---
-- Wakeup sepecified token's coroutine
-- @tparam any Sleep/Wait coroutine token
function sys:wakeup(token)
	return skynet.wakeup(token)
end

---
-- Get current application dir
function sys:app_dir()
	return lfs.currentdir().."/ioe/apps/"..self._app_name.."/"
	--return os.getenv("PWD").."/ioe/apps/"..self._app_name.."/"
end

---
-- Get Application SN
function sys:app_sn()
	local app_sn = self._app_sn
	if app_sn then
		return app_sn
	end

	app = dc.get("APPS", self._app_name)
	if app then
		app_sn = app.sn
	end
	if not app_sn then
		local cloud = snax.queryservice('cloud')
		app_sn = cloud.req.gen_sn(self._app_name)
	end
	self._app_sn = app_sn

	return self._app_sn
end

---
-- Get application configuration
function sys:get_conf(default_config)
	app = dc.get("APPS", self._app_name)
	local conf = {}
	if app and app.conf then
		conf = app.conf 
	end
	if not default_config then
		return conf
	end
	return setmetatable(conf, {__index = default_config})
end

---
-- Set application configuration
function sys:set_conf(config)
	app = dc.get("APPS", self._app_name)
	if app then
		app.conf = config
		dc.set("APPS", self._app_name, app)
		return  true
	end
end

--- Get cloud configuration api
-- @tparam string conf_name Cloud application configuration id
-- @tparam string ext Local saving file extension. e.g. csv conf xml. default csv
-- @tparam string dir Application template file saving directory. <current_path>/tpl
-- @treturn conf_api
function sys:conf_api(conf_name, ext, dir)
	local dir = self:app_dir()..(dir or 'tpl')
	app = dc.get("APPS", self._app_name)
	return conf_api:new(self, app.name, conf_name, ext, dir)
end

---
-- Get application name, version
-- @treturn string Application instance name
-- @treturn number Application version number
function sys:version()
	app = dc.get("APPS", self._app_name)
	return app.name, app.version
end

---
-- Generate device serial number
-- @tparam string device name used to generate serial number
function sys:gen_sn(dev_name)
	local cloud = snax.queryservice('cloud')
	return cloud.req.gen_sn(self._app_name.."."..dev_name)
end

---
-- Get system ID
function sys:id()
	return ioe.id()
end

---
-- Get hardware ID
function sys:hw_id()
	return ioe.hw_id()
end

---
-- Fire request to app self, which will call your app.response or on_req_<msg> if on_post does not exists
function sys:req(msg, ...)
	assert(self._wrap_snax)
	return self._wrap_snax.req.app_req(msg, ...)
end

---
-- Post message to app self, which will call your app.accept or on_post_<msg> if on_post does not exists
function sys:post(msg, ...)
	assert(self._wrap_snax)
	return self._wrap_snax.post.app_post(msg, ...)
end

--- POST to cloud
local CLOUD_WHITE_LIST_POST = {
	'enable_data_one_short',
	'enable_event',
	'download_cfg',
	'upload_cfg',
	'fire_data_snapshot',
	'batch_script',
}
--- 
-- Call cloud post actions
-- @tparam func string Action name
-- @tparam ... args Action parameters
function sys:cloud_post(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHITE_LIST_POST) do
		if v == func then
			found = true
			break
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cloud, err = snax.queryservice('cloud')
	if not cloud then
		return nil, err
	end

	local id = string.format(':APP_CLOUD_POST:%s-%0.2f]', self._app_name, skynet.time())
	cloud.post[func](id, ...)
	return true
end

local CLOUD_WHILTE_LIST_REQ = {}
--- 
-- Call cloud request actions
-- @tparam func string Action name
-- @tparam ... args Action parameters
function sys:cloud_req(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHILTE_LIST_REQ) do
		if v == func then
			found = true
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cloud, err = snax.queryservice('cloud')
	if not cloud then
		return nil, err
	end
	local id = string.format(':APP_CLOUD_POST:%s-%0.2f]', self._app_name, skynet.time())
	return cloud.req[func](...)
end

local CFG_WHITE_LIST_CALL = {
	'SAVE',
}
--- 
-- Call system cfg service actions
-- @tparam func string Action name
-- @tparam ... args Action parameters
function sys:cfg_call(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHILTE_LIST_REQ) do
		if v == func then
			found = true
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cfg, err = skynet.queryservice('CFG')
	if not cfg then
		return nil, err
	end
	return skynet.call(cfg, "lua", func, ...)
end

---
-- Set event fire threshold
-- @tparam count_per_min number The max count fired per minute
function sys:set_event_threshold(count_per_min)
	self._data_api:_set_event_threshold(count_per_min)
end

---
-- API initialiation function
-- @tparam app_name string Application instance name
-- @tparam mgr_snax api Application manager snax object
-- @tparam wrap_snax api Application snax object
function sys:initialize(app_name, mgr_snax, wrap_snax)
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax
	self._app_name = app_name
	self._app_sn = nil
	self._logger = logger:new(app_name)
	self._data_api = api:new(app_name, mgr_snax, self._logger)
end

---
-- Cleanup current object
function sys:cleanup()
	if self._data_api then
		self._data_api:cleanup()
	end
end

return sys
