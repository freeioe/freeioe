local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local httpdown = require 'httpdown'
local log = require 'utils.log'
local lfs = require 'lfs'
local datacenter = require 'skynet.datacenter'

local tasks = {}
local command = {}
local cloud = nil

local function get_target_folder(inst_name)
	return lfs.currentdir().."/iot/apps/"..inst_name.."/"
	--return os.getenv("PWD").."/iot/apps/"..inst_name
end

local function create_task(func, task_name, ...)
	skynet.fork(function(task_name, ...)
		tasks[coroutine.running()] = {
			name = task_name
		}
		func(...)
	end, task_name, ...)
end

local function create_download(app_name, version, cb)
	local app_name = app_name
	local cb = cb
	local down = function()
		local fn = "/tmp/"..app_name.."_"..version..".zip"
		local file, err = io.open(fn, "w+")
		if not file then
			return cb(nil, err)
		end

		local pkg_host = datacenter.get("CLOUD", "PKG_HOST_URL")

		local url = "/download/"..app_name.."/ver_"..version..".zip"
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return cb(nil, header)
		end
		file:write(body)
		file:close()
		cb(true, fn)
	end
	create_task(down, "Download App "..app_name)
end

local function log_info(lvl, ...)
	log[lvl](...)
	if cloud then
		cloud.post.install_log(lvl, ...)
	end
end

function command.upgrade_app(inst_name, version)
	create_task(function()
		print("XXXXXXXXXX")
		skynet.sleep(10000)
	end, "Upgrade App "..inst_name)
	return true
end

function command.install_app(name, version, inst_name)
	if datacenter.get("APPS", inst_name) then
		return nil, "Application already installed"
	end
	local appmgr = snax.uniqueservice("appmgr")
	local inst_name = inst_name
	local target_folder = get_target_folder(inst_name)
	lfs.mkdir(target_folder)

	create_download(name, version, function(r, info)
		if r then
			log_info("error", "Download application finished")
			os.execute("unzip -oq "..info.." -d "..target_folder)
			local r, err = appmgr.req.start(inst_name, {})
			if r then
				log_info("notice", "Application "..name.." started")
				datacenter.set("APPS", inst_name, {name=name, version=version})
			else
				log_info("error", "Failed to start App. Error: "..err)
			end
		else
			log_info("error", "Failed to download App. Error: "..info)
		end
	end)
	return true
end

function command.uninstall_app(inst_name)
	local appmgr = snax.uniqueservice("appmgr")
	local target_folder = get_target_folder(inst_name)

	local r, err = appmgr.req.stop(inst_name, "Uninstall App")
	if r then
		os.execute("rm -rf "..target_folder)
		datacenter.set("APPS", inst_name, nil)
		return true
	end
	return nil, err
end

function command.list_app()
	return datacenter.get("APPS")
end

function command.upgrade_core(version)
	create_download('iot', version, function(r, path)
		if r then
			os.execute("unzip "..path.." -d "..target_folder)
		end
	end)
	return true
end

function command.list()
	return tasks
end

function command.bind_cloud(handle, type)
	cloud = snax.bind(handle, type)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.lower(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register "UPGRADER"
end)

