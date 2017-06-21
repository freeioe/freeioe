local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'

local applist = {}

---
-- Return instance id
function response.start(name, ...)
	local inst = snax.newservice("ita", name)
	local r, err = inst.req.start(...)
	if not r then
		log.error("Failed start app. Error: "..err)
		return nil, "Failed start app. Error: "..err
	end

	applist[inst] = {
		name = name,
		cfg = cfg,
		m = r,
	}
	return inst
end

function response.stop(instance, ...)
	local inst = applist[instance]
	if not inst then
		return nil, "App instance "..instance.." does not exits!"
	end
	snax.kill(instance, ...)
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
