local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

local applist = {}
local mc_map = {}

---
-- Return instance id
function response.start(name, conf)
	local s = snax.self()
	local inst = snax.newservice("appwrap", name, conf, s.handle, s.type)
	local r, err = inst.req.start()
	if not r then
		log.error("Failed start app. Error: "..err)
		return nil, "Failed start app. Error: "..err
	end

	applist[name] = {
		inst = inst,
		conf = conf,
	}
	return inst
end

function response.stop(name, reason)
	local app = applist[name]
	if not app then
		return nil, "App instance "..name.." does not exits!"
	end
	snax.kill(app.inst, reason)
	applist[name] = nil
	return true
end

function response.list()
	return applist
end

function response.set_conf(inst, conf)
	local app = applist[inst]
	if not app or not app.inst then
		return nil, "There is no app instance name is "..inst
	end
	return app.inst.req.set_conf(conf)
end

function response.get_channel(name)
	local c = mc_map[string.upper(name)]
	if c then
		return c.channel
	end
	return nil, "No multicast channel for "..name
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

	skynet.fork(function()
		local apps = dc.get("APPS") or {}
		for k,v in pairs(apps) do
			snax.self().req.start(k, {})
		end
	end)
end

function exit(...)
	for k,v in applist do
		snax.kill(instance, "force")
	end
	dc.set("MC", "APP", "DATA", nil)
	dc.set("MC", "APP", "CTRL", nil)
	dc.set("MC", "APP", "COMM", nil)
	for k,v in mc_map do
		v:delete()
	end
	log.info("AppMgr service closed!")
end
