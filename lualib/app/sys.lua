local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local log = require 'utils.log'
local class = require 'middleclass'
local ioe = require 'ioe'
local api = require 'app.api'
local logger = require 'app.logger'
local conf_api = require 'app.conf.api'
local lfs = require 'lfs'

local sys = class("APP_MGR_SYS")
sys.API_VER = 6 -- 2019.09.28
sys.API_MIN_VER = 1

function sys:log(level, ...)
	return self._logger:log(level, ...)
end

function sys:logger()
	return self._logger
end

function sys:dump_comm(sn, dir, ...)
	local sn = sn or self:app_sn()
	return self._data_api:_dump_comm(sn, dir, ...)
end

function sys:fire_event(sn, level, type_, info, data, timestamp)
	return self._data_api:_fire_event(sn or self:app_sn(), level, type_, info, data or {}, timestamp or ioe.time())
end

function sys:fork(func, ...)
	skynet.fork(func, ...)
end

function sys:timeout(ms, func)
	return skynet.timeout(ms / 10, func)
end

function cancelable_timeout(ti, func)
	local function cb()
		if func then
			func()
		end
	end
	local function cancel()
		func = nil
	end
	skynet.timeout(ti, cb)
	return cancel
end


function sys:cancelable_timeout(ms, func)
	local cancel = cancelable_timeout(ms / 10, func)
	return cancel
end

-- Current Application exit
function sys:exit()
	skynet.exit()
end

-- System abort
function sys:abort()
	self._logger:warning("FreeIOE will be closed after 5 seconds!")
	ioe.abort(5000)
end

-- ms uptime
function sys:now()
	return skynet.now() * 10
end

function sys:fix_time()
	if skynet.fix_time then
		skynet.fix_time()
	else
		self._logger:warning("Reboot FreeIOE to fix time diff issue!")
		self:abort()
	end
end

-- seconds (UTC now)
function sys:time()
	return ioe.time()
end

-- seconds (UTC system start time)
function sys:start_time()
	return ioe.starttime()
end

function sys:yield()
	return skynet.yield()
end

function sys:sleep(ms, token)
	local ts = math.floor(ms / 10)
	return skynet.sleep(ts, token)
end

function sys:data_api()
	return self._data_api
end

function sys:self_co()
	return coroutine.running()
end

function sys:wait(token)
	return skynet.wait(token)
end

function sys:wakeup(token)
	return skynet.wakeup(token)
end

function sys:app_dir()
	return lfs.currentdir().."/ioe/apps/"..self._app_name.."/"
	--return os.getenv("PWD").."/ioe/apps/"..self._app_name.."/"
end

-- Application SN
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

function sys:get_conf(default_config)
	app = dc.get("APPS", self._app_name)
	local conf = {}
	if app and app.conf then
		conf = app.conf 
	end
	return setmetatable(conf, {__index = default_config})
end

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
	return conf_api:new(app.name, conf_name, ext, dir)
end

function sys:version()
	app = dc.get("APPS", self._app_name)
	return app.name, app.version
end

--[[
-- Generate device application
--]]
function sys:gen_sn(dev_name)
	local cloud = snax.queryservice('cloud')
	return cloud.req.gen_sn(self._app_name.."."..dev_name)
end

-- System ID
function sys:id()
	return ioe.id()
end

function sys:hw_id()
	return ioe.hw_id()
end

-- Fire request to app self, which will call your app.response or on_req_<msg> if on_post does not exists
function sys:req(msg, ...)
	assert(self._wrap_snax)
	return self._wrap_snax.req.app_req(msg, ...)
end

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

function sys:set_event_threshold(count_per_min)
	self._data_api:_set_event_threshold(count_per_min)
end

function sys:initialize(app_name, mgr_snax, wrap_snax)
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax
	self._app_name = app_name
	self._data_api = api:new(app_name, mgr_snax)
	self._app_sn = nil
	self._logger = logger:new(log, app_name)
end

function sys:cleanup()
	if self._data_api then
		self._data_api:cleanup()
	end
end

return sys
