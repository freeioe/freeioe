local skynet = require "skynet"
local snax = require "skynet.snax"
local datacenter = require "skynet.datacenter"
local log = require 'utils.log'

local arg = table.pack(...)
assert(arg.n <= 2)
local batch_id = arg[1]

local tasks = {}

local function gen_task_id(cate, info)
	log.info('::RunBatch:: BatchScript Create sub task: ', info)
	local id = batch_id .. '.' .. #tasks
	tasks[#tasks + 1] = {
		id = id,
		cate = cate or 'app',
		info = info,
	}
	return id
end

local function post_action_result(channel, id, result, info)
	local cloud = snax.queryservice('cloud')
	cloud.post.action_result(channel, id, result, info)
end

local batch_env = {
	INSTALL_APP = function(inst, name, version, conf, sn)
		local id = gen_task_id('app', "Install application "..name.." as "..inst)
		assert(inst and name and version)
		local r, err = skynet.call(".upgrader", "lua", "install_app", id, {
			name = name,
			inst = inst,
			version = version,
			conf = conf,
			sn = sn
		})
		if not r then
			log.error("::RunBatch:: Call install_app failed.", err)
		end
	end,
	REMOVE_APP = function(inst)
		local id = gen_task_id('app', "Remove application instance "..inst)
		local r, err = skynet.call(".upgrader", "lua", "uninstall_app", id, {
			inst = inst,
		})
		if not r then
			log.error("::RunBatch:: Call uninstall_app failed.", err)
		end
	end,
	UPGRADE_APP = function(inst, version, conf, sn)
		local id = gen_task_id('app', "Upgrade application instance "..inst.." to version "..version)
		local r, err = skynet.call(".upgrader", "lua", "upgrade_app", id, {
			inst = inst,
			version = version,
			sn = sn,
			conf = conf
		})
		if not r then
			log.error("::RunBatch:: Call upgrade_app failed.", err)
		end
	end,
	CONF_APP_SCRIPT = function(inst, script)
		local id = gen_task_id('app', "Config application "..inst)
		local appmgr = snax.queryservice('appmgr')
		local conf, err = appmgr.req.get_conf(inst)
		if not conf then
			post_action_result('app', id, nil, err)
			return
		end
		local f, err = load(script, 'conf_app_script'..inst, 't', {conf=conf})
		if not f then
			post_action_result('app', id, nil, err)
			return
		end

		local new_conf, err = f(conf)
		if not new_conf then
			post_action_result('app', id, nil, err)
			return
		end
		local r, err = appmgr.req.set_conf(inst, conf)
		post_action_result('app', id, r, err or "Done")
	end,
	CONF_APP = function(inst, conf)
		local id = gen_task_id('app', "Config application "..inst)
		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.set_conf(inst, conf)
		post_action_result('app', id, r, err or "Done")
	end,
	SET_APP_OPTION = function(inst, option, value)
		local id = gen_task_id('app', "Set application "..inst..' option')
		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.app_option(inst, option, value)
		post_action_result('app', id, r, err or "Done")
	end,
	RENAME_APP = function(inst, new_name)
		local id = gen_task_id('app', "Rename application "..inst)
		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.app_rename(inst, new_name)
		post_action_result('app', id, r, err or "Done")
	end,
	CLEAN_APPS = function()
		local appmgr = snax.queryservice('appmgr')
		local list = appmgr.req.list()
		for k, _ in pairs(list) do
			REMOVE_APP(k)
		end
	end,
	UPGRADE_EXT = function(inst, version)
		local id = gen_task_id('app', "Upgrade extension instance "..inst.." to version "..version)
		local r, err = skynet.call(".ioe_ext", "lua", "upgrade_ext", id, {
			inst = inst,
			version = version,
		})
		if not r then
			local err = "::RunBatch:: Call upgrade_ext failed. "..err
			log.error(err)
		end
	end,
	UPGRADE_SYS = function(version, skynet_version, need_ack)
		local id = gen_task_id('sys', "Upgrade system to ver "..(version or 'N/A')..", skynet "..(skynet_version or 'N/A'))
		if not version then
			post_action_result('app', id, false, "Version is required!")
			return
		end
		local no_ack = not need_ack
		local skynet_args = skynet_version and {version=skynet_version} or nil
		local r, err = skynet.call(".upgrader", "lua", "upgrade_core", id, {
			version = version,
			no_ack = no_ack,
			skynet = skynet_args,
		})
		if not r then
			local err = "::RunBatch:: Call upgrade_core failed. "..err
			log.error(err)
		end
	end,
	TEST = function(...)
		print(...)
		log.debug("::RunBatch::", ...)
	end,
	LOG = function(level, ...)
		log[level]("::RunBatch::", ...)
	end,
}

skynet.start(function()
	log.notice("::RunBatch:: Batch script: ", batch_id)
	local script = arg.n == 2 and arg[2] or datacenter.get("BATCH", batch_id, "script")
	assert(script)

	--- Loading script string
	local f, err = load(script, nil, "bt", batch_env)
	local cloud = snax.queryservice('cloud')
	if not f then
		local err = "::RunBatch:: Loading batch script failed. "..err
		log.error(err)
		cloud.post.action_result("batch_script", batch_id, false, err)
	else
		local r, err = xpcall(f, debug.traceback)
		if not r then
			log.warning("::RunBatch:: BATCH run error", err)
			cloud.post.action_result("batch_script", batch_id, false, err)
		else
			cloud.post.action_result("batch_script", batch_id, true, tasks)
		end
	end

	--- Cleanup script
	datacenter.set("BATCH", batch_id, nil)
end)
