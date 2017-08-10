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
		log.trace('Start Download From URL:', pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return cb(nil, header)
		end
		if status < 200 or status > 400 then
			return cb(nil, "Download failed, status code "..status)
		end
		file:write(body)
		file:close()
		cb(true, fn)
	end
	create_task(down, "Download App "..app_name)
end

local function install_result(id, result, ...)
	if result then
		log.info(...)
	else
		log.error(...)
	end

	if cloud then
		cloud.post.action_result("app", id, result, ...)
	end
end

function command.upgrade_app(args)
	local id = args.id
	local inst_name = args.inst
	local version = args.version
	create_task(function()
		print("XXXXXXXXXX")
		skynet.sleep(10000)
	end, "Upgrade App "..inst_name)
	return true
end

function command.install_app(id, args)
	local name = args.name
	local inst_name = args.inst
	local version = args.version
	local sn = args.sn or cloud.req.gen_sn(inst_name)
	local conf = args.conf

	if datacenter.get("APPS", inst_name) then
		local err = "Application already installed"
		install_result(id, false, "Failed to install App. Error: "..err)
		return
	end
	local appmgr = snax.uniqueservice("appmgr")
	local inst_name = inst_name
	local target_folder = get_target_folder(inst_name)
	lfs.mkdir(target_folder)

	create_download(name, version, function(r, info)
		if r then
			log.debug("Download application finished")
			os.execute("unzip -oq "..info.." -d "..target_folder)
			local r, err = appmgr.req.start(inst_name, {})
			if r then
				datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf})
				install_result(id, true, "Application installtion is done")
			else
				os.execute("rm -rf "..target_folder)
				install_result(id, false, "Failed to start App. Error: "..err)
			end
		else
			install_result(id, false, "Failed to download App. Error: "..info)
		end
	end)
end

function command.uninstall_app(id, args)
	local inst_name = args.inst

	local appmgr = snax.uniqueservice("appmgr")
	local target_folder = get_target_folder(inst_name)

	local r, err = appmgr.req.stop(inst_name, "Uninstall App")
	if r then
		os.execute("rm -rf "..target_folder)
		datacenter.set("APPS", inst_name, nil)
		install_result(id, true, "Application uninstall is done")
	else
		install_result(id, false, "Application uninstall failed, Error: "..err)
	end
end

function command.list_app()
	return datacenter.get("APPS")
end

function command.upgrade_core(id, args)
	local version = args.version

	create_download('iot', version, function(r, path)
		if r then
			os.execute("unzip "..path.." -d "..target_folder)
		end
	end)
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

