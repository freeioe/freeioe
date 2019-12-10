local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local ioe = require 'ioe'
local event = require 'app.event'
local cjson = require 'cjson.safe'

local applist = {}
local mc_map = {}
local listeners = {}
local closing = false
local sys_app = 'ioe'

local function fire_exception_event(app_name, info, data)
	local data = data or {}
	data.app = app_name
	return snax.self().post.fire_event(app_name, ioe.id(), event.LEVEL_ERROR, event.EVENT_APP, info, data)
end

---
-- Return instance id
function response.start(name, conf)
	log.info("::AppMgr:: Strat application "..name)
	-- Get application list item by name
	applist[name] = applist[name] or {}
	local app = applist[name]

	--- check if already started
	if app.inst then
		log.debug("::AppMgr:: Application already started "..name, app.inst)
		return app.inst
	end

	--- Set the configuration if it changed
	app.conf = conf or app.conf

	-- Create application instance
	local mgr_snax = snax.self()
	local inst, err = snax.newservice("appwrap", name, app.conf, mgr_snax.handle, mgr_snax.type)
	assert(not app.inst, "Bug found when starting application!!")

	--- Set the instance and last ping time
	app.inst = inst
	app.last = skynet.time()

	--- Call the applicaiton start
	local pr, r, err = pcall(inst.req.start)
	if not pr then
		local info = "::AppMgr:: Failed during start app "..name..". Error: "..tostring(r)
		log.error(info)
		fire_exception_event(name, "Failed during start app "..name, {info=app, err=r})
		app.inst = nil
		app.last = nil
		return nil, info
	end
	if not r then
		local info = "::AppMgr:: Failed to start app "..name..". Error: "..tostring(err)
		log.error(info)
		fire_exception_event(name, "Failed to start app "..name, {info=app, err=err})
		snax.kill(inst, "Start failed!")
		app.inst = nil
		app.last = nil
		return nil, info
	end

	if not app.inst then
		-- Applicaiton stoped during starting
		return
	end

	--- Set the proper start/last time
	app.start = skynet.time()
	app.last = skynet.time()

	--- Tell the applicaiton status listeners
	for handle, srv in pairs(listeners) do
		srv.post.app_event('start', name, inst.handle)
	end

	return inst
end

function response.stop(name, reason)
	local app = applist[name]
	if not app then
		-- For some hacks that applicaiton exists but not loaded.
		if dc.get("APPS", name) then
			return true
		end
		return nil, "App instance "..name.." does not exits!"
	end

	if app.inst then
		local force_kill = function()
			log.warning("::AppMgr:: Force to kill app "..name.." as it is not closed within 60 seconds")
			skynet.kill(app.inst.handle)

			app.inst = nil
		end

		skynet.timeout(6000, function()
			if force_kill then
				force_kill()
			end
		end)

		skynet.fork(function()
			snax.kill(app.inst, reason)
			app.inst = nil
			force_kill = nil
		end)

		while app.inst do
			skynet.sleep(100)
		end
	end

	for handle, srv in pairs(listeners) do
		srv.post.app_event('stop', name, reason)
	end

	return true
end

-- Used by application for restart its self
function response.restart(name, reason)
	local name = name
	local reason = reason or "Restart"

	local r, err = snax.self().req.stop(name, reason)
	if not r then
		log.warning("::AppMgr:: Failed to stop application when restart it")
		return false, "Failed to stop application"
	else
		--- Only start it if stop successfully
		return snax.self().req.start(name)
	end
end

function response.list()
	return applist
end

function response.app_inst(name)
	local app = applist[name]
	if not app then
		return nil, "Application does not exits"
	end
	return app.inst
end

function response.set_conf(inst, conf)
	local app = applist[inst]
	if not app then
		return nil, "There is no app instance name is "..inst
	end

	app.conf = conf or {}
	dc.set("APPS", inst, 'conf', app.conf)
	if not app.inst then
		snax.self().post.app_event('conf', inst, conf)
		return true
	end

	local r, err = app.inst.req.set_conf(conf)
	if r then
		snax.self().post.app_event('conf', inst, conf)
	end
	return r, err
end

function response.get_conf(inst)
	local app = applist[inst]
	if not app then
		return nil, "There is no app instance name is "..inst
	end
	return app.conf
end

function response.app_option(inst, option, value)
	if dc.get("APPS", inst) then
		dc.set("APPS", inst, option, value)
		snax.self().post.app_event('option', inst, option, value)
		return true
	else
		return nil, "Application instance does not exits!"
	end
end

function response.app_rename(inst, new_name, reason)
	if not inst or not new_name then
		return nil, "Incorrect params"
	end
	local reason = reason or "Rename from "..inst.." to "..new_name
	if not applist[inst] then
		return nil, "App not exists!"
	end

	local r, err = snax.self().req.stop(inst, reason)
	if not r then
		return nil, err
	end
	return skynet.call(".upgrader", "lua", "rename_app", "from_cloud", {inst=inst, new_name=new_name})
end

function response.get_channel(name)
	local c = mc_map[string.upper(name)]
	if c then
		return c.channel
	end
	return nil, "No multicast channel for "..name
end

function accept.app_modified(inst, from)
	log.warning("::AppMgr:: Application has modified from "..from)
	local app = applist[inst]
	if not app then
		return
	end

	local islocal = dc.get("APPS", inst, 'islocal')
	if islocal then
		return
	end

	dc.set("APPS", inst, 'islocal', 1)
	snax.self().post.app_event('option', inst, 'islocal', 1)
end

function accept.app_start(inst)
	local v = dc.get("APPS", inst)
	if not v then return end
	skynet.fork(function()
		snax.self().req.start(inst, v.conf or {})
	end)
end

function accept.app_stop(inst, reason)
	local v = dc.get("APPS", inst)
	if not v then return end
	skynet.fork(function()
		snax.self().req.stop(inst, reason or 'stop application from accept.app_stop')
	end)
end

function accept.app_restart(inst, reason)
	local v = dc.get("APPS", inst)
	if not v then return end
	skynet.fork(function()
		snax.self().req.restart(inst, reason or 'restart application from accept.app_stop')
	end)
end

function accept.app_event(event, inst_name, ...)
	if event == 'create' then
		if not applist[inst_name] then
			applist[inst_name] = {conf={}}
		end
	end
	if event == 'rename' then
		local new_name = select(1, ...)
		applist[inst_name] = nil

		local auto = dc.get("APPS", new_name, "auto")
		if tonumber(auto or 1) ~= 0 then
			snax.self().post.app_start(new_name)
		end
	end

	for handle, srv in pairs(listeners) do
		srv.post.app_event(event, inst_name, ...)
	end
end

function accept.app_heartbeat(inst, time)
	--log.debug("::AppMgr:: Application heartbeat received from", inst, time)
	if applist[inst] then
		applist[inst].last = time or skynet.time()
	end
end

function accept.app_heartbeat_check()
	for k, v in pairs(applist) do
		if v.inst then
			--- 180 seconds timeout, three times for app heart beart
			if skynet.time() - v.last > 180 + 20 then
				v.last = skynet.time() + 180 --- mark it as not timeout
				log.notice("::AppMgr:: App heartbeat timeout! Inst:", k)

				local data = {app=k, inst=v.inst, last=v.last, time=os.time()}
				snax.self().post.fire_event(sys_app, ioe.id(), event.LEVEL_ERROR, event.EVENT_APP, 'heartbeat timeout', data)
				snax.self().req.restart(k, 'heartbeat timeout')
			end
		end
	end
end

---- for event stuff
-- @handle source snax handle
-- @handle source snax type
-- @fire_list fire application list inside post
function accept.listen(handle, type, fire_list)
	local snax_inst = snax.bind(handle, type)
	listeners[handle] = snax_inst
	if fire_list then
		snax_inst.post.app_list(applist)
	end
	return true
end

function accept.unlisten(handle)
	listeners[handle] = nil
	return true
end

function accept.fire_event(app_name, sn, level, type_, info, data, timestamp)
	log.trace("::AppMgr:: fire_event", app_name, sn, level, type_, info, timestamp, cjson.encode(data))
	assert(sn and level and type_ and info)
	local event_chn = mc_map.EVENT
	local type_ = event.type_to_string(type_)
	if event_chn then
		skynet.timeout(200, function()
			event_chn:publish(app_name, sn, level, type_, info, data or {}, timestamp or ioe.time())
		end)
	end
end

function accept.close_all(reason)
	log.warning("::AppMgr:: service is closing all apps. reason:"..(reason or "UKNOWN"))
	for k, v in pairs(applist) do
		if v.inst then
			snax.self().post.app_stop(k, reason)
		end
	end
end

function init(...)
	log.info("::AppMgr:: App manager service starting...")

	local chn = mc.new()
	dc.set("MC", "APP", "DATA", chn.channel)
	mc_map['DATA'] = chn

	local chn = mc.new()
	dc.set("MC", "APP", "CTRL", chn.channel)
	mc_map['CTRL'] = chn

	local chn = mc.new()
	dc.set("MC", "APP", "COMM", chn.channel)
	mc_map['COMM'] = chn

	local chn = mc.new()
	dc.set("MC", "APP", "STAT", chn.channel)
	mc_map['STAT'] = chn

	local chn = mc.new()
	dc.set("MC", "APP", "EVENT", chn.channel)
	mc_map['EVENT'] = chn

	skynet.fork(function()
		local apps = dc.get("APPS") or {}
		for k,v in pairs(apps) do
			if tonumber(v.auto or 1) ~= 0 then
				snax.self().post.app_start(k)
			else
				applist[k] = { conf = v.conf }
			end
		end
		if not apps[sys_app] then
			snax.self().req.start(sys_app, {})
		end
	end)
	skynet.fork(function()
		skynet.sleep(1000) -- ten seconds
		while not closing do
			snax.self().post.app_heartbeat_check()
			skynet.sleep(500) -- five seconds.
		end
	end)
end

function exit(...)
	closing = true
	for k,v in pairs(applist) do
		if v.inst then
			snax.kill(v.inst, "force")
			v.inst = nil
		end
	end
	applist = {}
	dc.set("MC", "APP", "DATA", nil)
	dc.set("MC", "APP", "CTRL", nil)
	dc.set("MC", "APP", "COMM", nil)
	dc.set("MC", "APP", "STAT", nil)
	dc.set("MC", "APP", "EVENT", nil)
	for k,v in pairs(mc_map) do
		v:delete()
	end
	mc_map = {}
	listeners = {}
	log.info("::AppMgr:: service closed!")
end
