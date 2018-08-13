local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local ioe = require 'ioe'
local event = require 'app.event'

local applist = {}
local mc_map = {}
local reg_map = {}
local closing = false
local sys_app = 'ioe'

local function fire_exception_event(app_name, info, data)
	local data = data or {}
	data.app = app_name
	return snax.self().post.fire_event(app_name, sys_id, event.LEVEL_ERROR, event.EVENT_APP, info, data)
end

---
-- Return instance id
function response.start(name, conf)
	local app = applist[name] or {}

	if app.inst then
		return app.inst
	end
	app.conf = conf or app.conf
	applist[name] = app

	local s = snax.self()
	local inst, err = snax.newservice("appwrap", name, app.conf, s.handle, s.type)

	local r, err = inst.req.start()
	if not r then
		local info = "Failed to start app "..name..". Error: "..err
		log.error(info)
		fire_exception_event(name, "Failed to start app"..name, {info=app, err=err})
		snax.kill(inst, "Start failed!")
		return nil, info
	end

	app.inst = inst
	app.last = skynet.time()

	for handle, srv in pairs(reg_map) do
		srv.post.app_started(name, inst.handle)
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
		snax.kill(app.inst, reason)
		app.inst = nil
	end

	for handle, srv in pairs(reg_map) do
		srv.post.app_stoped(name)
	end

	return true
end

-- Used by application for restart its self
function response.restart(name, reason)
	local name = name
	local reason = reason or "Restart"
	skynet.timeout(10, function()
		snax.self().req.stop(name, reason)
		snax.self().req.start(name)
	end)
	return true
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
	if not app or not app.inst then
		return nil, "There is no app instance name is "..inst
	end

	app.conf = conf or {}
	local r, err = app.inst.req.set_conf(conf)
	return r, err
end

function response.get_conf(inst)
	local app = applist[inst]
	if not app or not app.inst then
		return nil, "There is no app instance name is "..inst
	end
	return app.conf
end

function response.app_option(inst, option, value)
	if dc.get("APPS", inst) then
		dc.set("APPS", inst, option, value)
		return true
	else
		return nil, "Application instance does not exits!"
	end
end

function response.get_channel(name)
	local c = mc_map[string.upper(name)]
	if c then
		return c.channel
	end
	return nil, "No multicast channel for "..name
end

function accept.app_modified(inst, from)
	log.warning("Application has modified from "..from)
	local app = applist[inst]
	if not app then
		return
	end

	local islocal = dc.get("APPS", inst, 'islocal')
	if islocal then
		return
	end

	dc.set("APPS", inst, 'islocal', 1)
end

function accept.app_start(inst)
	local v = dc.get("APPS", inst)
	skynet.fork(function()
		snax.self().req.start(inst, v.conf or {})
	end)
end

function accept.app_create(inst, opts)
	if not applist[inst] then
		applist[inst] = {}
	end
end

function accept.app_heartbeat(inst, time)
	--log.debug("Application heartbeat received from", inst, time)
	if applist[inst] then
		applist[inst].last = time or skynet.time()
	end
end

function accept.app_heartbeat_check()
	for k, v in pairs(applist) do
		if v.inst then
			if v.last - skynet.time() > 60 then
				local data = {app=k, inst=v.inst, last=v.last, time=skynet.time()}
				snax.self().post.fire_event(sys_app, ioe.id(), event.LEVEL_ERROR, event.EVENT_APP, 'heartbeat timeout', data)
				snax.self().req.restart(k, 'heartbeat timeout')
			end
		end
	end
end

function accept.reg_snax(handle, type)
	local snax_inst = snax.bind(handle, type)
	reg_map[handle] = snax_inst
	snax_inst.post.app_list(applist)
	return true
end

function accept.unreg_snax(handle)
	reg_map[handle] = nil
	return true
end

function accept.fire_event(app_name, sn, level, type_, info, data, timestamp)
	log.trace("AppMgr fire_event", app_name, sn, level, type_, info, data, timestamp)
	assert(sn and level and type_ and info)
	local event_chn = mc_map.EVENT
	if event_chn then
		skynet.timeout(200, function()
			event_chn:publish(app_name, sn, level, type_, info, data or {}, timestamp or skynet.time())
		end)
	end
end

function init(...)
	log.info("AppMgr service starting...")

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
			snax.self().req.start(sys_app)
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
	reg_map = {}
	log.info("AppMgr service closed!")
end
