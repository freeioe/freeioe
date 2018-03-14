local skynet = require "skynet"
local datacenter = require "skynet.datacenter"
local cjson = require "cjson.safe"
local log = require 'utils.log'

local arg = table.pack(...)
assert(arg.n <= 2)
local id = arg[1]

local batch_env = {
	INSTALL_APP = function(inst, name, version, sn, conf)
		assert(inst and name and version)
		local r, err = skynet.call("UPGRADER", "lua", "install_app", id, {
			name = name,
			inst = inst,
			version = version,
			sn = sn,
			conf = conf
		})
	end,
	REMOVE_APP = function(inst)
		local r, err = skynet.call("UPGRADER", "lua", "uninstall_app", id, {
			inst = inst,
		})
	end,
	UPGRADE_APP = function(inst, version, sn, conf)
		local r, err = skynet.call("UPGRADER", "lua", "upgrade_app", id, {
			inst = inst,
			version = version,
			sn = sn,
			conf = conf,
		})
	end,
	UPGRADE_SYS = function(version, skynet_version, need_ack)
		assert(version)
		local no_ack = need_ack and true or false
		local skynet_args = skynet_version and {version=skynet_version} or nil
		local r, err = skynet.call("UPGRADE", "lua", "upgrade_core", id, {
			version = version,
			no_ack = no_ack,
			skynet = skynet_args,
		})
	end,
	TEST = function(...)
		log.debug(...)
	end,
}

skynet.start(function()
	log.notice("Batch script: ", id)
	local script = arg.n == 2 and arg[2] or datacenter.get("BATCH", id, "script")
	assert(script)
	print(script)

	local f, err = load(script, nil, "bt", batch_env)
	if not f then
		log.error("Loading batch script failed", err)
	else
		local r, err = xpcall(f, debug.traceback)
		if not r then
			datacenter.set("BATCH_RESULT", id, err)
		else
			datacenter.set("BATCH_RESULT", id, "DONE")
		end
		datacenter.set("BATCH", id, nil)
	end
end)
