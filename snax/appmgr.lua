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

	applist[inst] = {
		name = name,
		conf = conf,
	}
	return inst
end

function response.stop(instance, reason)
	local inst = applist[instance]
	if not inst then
		return nil, "App instance "..instance.." does not exits!"
	end
	snax.kill(instance, reason)
	applist[instance] = nil
	return true
end

function response.list()
	return applist
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
	dc.set("MC", "APP", "DATA", channel.channel)
	mc_map['DATA'] = chn
	local chn = mc.new()
	dc.set("MC", "APP", "CTRL", channel.channel)
	mc_map['CTRL'] = chn
	local chn = mc.new()
	dc.set("MC", "APP", "COMM", channel.channel)
	mc_map['COMM'] = chn
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
