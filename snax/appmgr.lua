local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'

local applist = {}

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
		mgr = mgr,
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

function init(...)
	log.info("AppMgr service starting...")
end

function exit(...)
	for k,v in applist do
		snax.kill(instance, "force")
	end
	log.info("AppMgr service closed!")
end
