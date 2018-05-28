local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

local applist = {}
local mc_map = {}
local reg_map = {}

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
		log.error("Failed to start app. Error: "..err)
		snax.kill(inst, "Start failed!")
		return nil, "Failed to start app. Error: "..err
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

function accept.app_option(inst, option, value)
	dc.set("APPS", inst, option, value)
	return true
end

function accept.app_create(inst, opts)
	if not applist[inst] then
		applist[inst] = {}
	end
end

function accept.app_heartbeat(inst, time)
	--log.debug("Application heartbeat received from", inst, time)
	if applist[inst] then
		applist[inst].last = time
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
		if not apps['iot'] then
			snax.self().req.start('iot')
		end
	end)
end

function exit(...)
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
