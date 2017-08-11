local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local httpdown = require 'httpdown'
local log = require 'utils.log'
local helper = require 'utils.helper'
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

local function create_download(app_name, version, md5, cb, ext)
	local app_name = app_name
	local cb = cb
	local ext = ext or ".zip"
	local down = function()
		local path = "/tmp/"..app_name.."_"..version..ext
		local file, err = io.open(path, "w+")
		if not file then
			return cb(nil, err)
		end

		local pkg_host = datacenter.get("CLOUD", "PKG_HOST_URL")

		local url = "/download/"..app_name.."/"..version..ext
		log.trace('Start Download From URL:', pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return cb(nil, tostring(header))
		end
		if status < 200 or status > 400 then
			return cb(nil, "Download failed, status code "..status)
		end
		file:write(body)
		file:close()
		local sum = helper.md5sum(path)
		log.trace("Downloaded file md5 sum", sum)
		if md5 and sum ~= md5 then
			return cb(nil, "Check md5 sum failed, expected:\t"..md5.."\t Got:\t"..sum)
		end
		cb(true, path)
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
	local version = args.version or 'latest'
	local sn = args.sn or cloud.req.gen_sn(inst_name)
	local conf = args.conf
	local md5 = args.md5

	if datacenter.get("APPS", inst_name) then
		local err = "Application already installed"
		install_result(id, false, "Failed to install App. Error: "..err)
		return
	end
	local appmgr = snax.uniqueservice("appmgr")
	local inst_name = inst_name
	local target_folder = get_target_folder(inst_name)
	lfs.mkdir(target_folder)

	create_download(name, version, md5, function(r, info)
		if r then
			log.debug("Download application finished")
			os.execute("unzip -oq "..info.." -d "..target_folder)
			datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf})
			local r, err = appmgr.req.start(inst_name, conf)
			if r then
				install_result(id, true, "Application installtion is done")
			else
				datacenter.set("APPS", inst_name, nil)
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

local function get_core_name(name, platform)
	local name = name
	local platform = platform or os.getenv("IOT_PLATFORM")
	if platform then
		name = platform.."_"..name
	end
	return name
end

local function download_upgrade_skynet(id, args, cb)
	local is_windows = package.config:sub(1,1) == '\\'
	local version = args.version or 'latest'
	local kname = get_core_name('skynet', args.platform)

	create_download(kname, version, md5, function(r, info)
		if r then
			cb(info)
		else
			install_result(id, false, "Failed to download App. Error: "..info)
		end
	end, ".tar.gz")

end

local function get_ps_e()
	local r, status, code = os.execute("ps -e")
	if not r then
		return "ps"
	end
	return "ps -e"
end

local function start_upgrade_proc(iot_path, skynet_path)
	assert(iot_path)
	log.warning("Core System Upgrade....")
	log.trace(iot_path, skynet_path)
	local ps_e = get_ps_e()

	local base_dir = os.getenv('IOT_DIR') or lfs.currentdir().."/../"
	local f, err = io.open(base_dir.."/upgrade.sh", "w+")
	if not f then
		print(base_dir.."/upgrade.sh", err)
		return nil, err
	end
	f:write("sleep 10\n")
	f:write("cd "..base_dir.."\n")
	if skynet_path then
		f:write("cd skynet\n")
		f:write("tar xzvf "..skynet_path.."\n")
		f:write("cd -\n")
	end
	f:write("cd skynet_iot\n")
	f:write("tar xzvf "..iot_path.."\n")
	f:write("cd -\n")
	f:write("cd skynet\n")
	f:write("./skynet iot/config &\n")
	f:write("cd -\n")

	f:write("sleep 5\n")
	f:write(ps_e.." | grep skynet | grep -v grep\n")
	f:write("if [ $? -eq 0 ]\nthen\n")
	f:write("\techo \"skynet process exits......\"\n")
	f:write("\tcp -f "..iot_path.." ./skynet_iot.tar.gz\n")
	if skynet_path then
		f:write("\tcp -f "..skynet_path.." ./skynet.tar.gz\n")
	end
	f:write("\techo \"upgrade is done!\"\n")
	f:write("else\n\tcd skynet_iot\n\ttar xzvf ../skynet_iot.tar.gz\n\tcd -\n")
	if skynet_path then
		f:write("\tcd skynet\n\ttar xzvf ../skynet.tar.gz\n\tcd -\n")
	end
	f:write("\t./skynet iot/config &\n")
	f:write("\tcd -\n")
	f:write("\techo \"rollback done\"\n")
	f:write("fi\n\n")
	f:close()
end

function command.upgrade_core(id, args)
	local is_windows = package.config:sub(1,1) == '\\'
	local version = args.version or 'latest'
	local md5 = args.md5
	local skynet = args.skynet

	create_download('skynet_iot', version, md5, function(r, info)
		if r then
			if skynet then
				download_upgrade_skynet(id, skynet, function(path) start_upgrade_proc(info, path) end)
			else
				start_upgrade_proc(path)
			end
		else
			install_result(id, false, "Failed to download App. Error: "..info)
		end
	end, ".tar.gz")
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

