local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local datacenter = require 'skynet.datacenter'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local httpdown = require 'httpdown'
local pkg_api = require 'pkg_api'
local lfs = require 'lfs'

local tasks = {}
local installed = {}
local command = {}

local get_target_folder = pkg_api.get_ext_folder
local get_target_root = pkg_api.get_ext_root
local get_ext_version = pkg_api.get_ext_version
local parse_version_string = pkg_api.parse_version_string
local get_app_target_folder = pkg_api.get_app_folder

local function make_inst_name(lib_name, version)
	local version = version or 'latest'
	return lib_name..'.'..version
end

local function parse_inst_name(inst_name)
	if string.len(inst_name) > 8 and string.sub(inst_name, -7) == '.latest' then
		return string.sub(inst_name, 1, -8), 'latest'
	end
	return string.match(inst_name, '^(.+).(%d+)$')
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
	local down = pkg_api.create_download_func(app_name, version, ".tar.gz", cb, true)
	create_task(down, "Download Extension "..app_name)
end


local function get_app_depends(app_inst)
	local exts = {}
	local dir = get_app_target_folder(app_inst)
	local f, err = io.open(dir.."/depends.txt", "r")
	if f then
		for line in f:lines() do
			local name, version = string.match(line, '^([^:]+):(%d+)$')
			name = name or line
			version = version or 'latest'
			exts[name] = version
		end
		f:close()
	end
	return exts 
end

local function install_depends_to_app_ext(ext_inst, app_inst, folder)
	local src_folder = get_target_folder(ext_inst)..folder.."/"
	if lfs.attributes(src_folder, 'mode') ~= 'directory' then
		return
	end
	local target_folder = get_app_target_folder(app_inst)..folder.."/"
	lfs.mkdir(target_folder)
	for filename in lfs.dir(src_folder) do
		if filename ~= '.' and filename ~= '..' then
			local path = src_folder..filename
			if lfs.attributes(path, 'mode') == 'file' then
				local lnpath = target_folder..filename
				os.execute("rm -f "..lnpath)
				log.debug('Link ', path, lnpath)
				os.execute("ln -s "..path.." "..lnpath)
			end
		end
	end
end

local function install_depends_to_app(ext_inst, app_inst)
	log.debug("Try to install "..ext_inst.." to "..app_inst)
	install_depends_to_app_ext(ext_inst, app_inst, 'luaclib')
	install_depends_to_app_ext(ext_inst, app_inst, 'bin')
end

function remove_depends(inst)
	log.warning('Remove Extension', inst)
	installed[inst] = nil
	local target_folder = get_target_folder(inst)
	os.execute("rm -rf "..target_folder)
end

local function list_installed()
	local list = {}
	local root = get_target_root()
	for filename in lfs.dir(root) do
		if filename ~= '.' and filename ~= '..' then
			if lfs.attributes(root..filename, 'mode') == 'directory' then
				local name, version = parse_inst_name(filename)
				log.debug('Installed Extension', name, version)
				list[filename] = {
					name = name,
					version = version
				}
				if version == 'latest' then
					list[filename].real_version = get_ext_version(filename)
				end
			end
		end
	end
	return list
end

local function list_depends()
	local app_list = datacenter.get("APPS")
	local depends = {}
	for app_inst, v in pairs(app_list) do
		local exts = get_app_depends(app_inst)
		for name, version in pairs(exts) do
			local inst_name = make_inst_name(name, version)
			local dep = depends[inst_name] or {}
			dep[#dep + 1] = app_inst
			depends[inst_name] = dep
		end
	end
	return depends
end

---
-- Check installed exts whether its required application exists for not
local function auto_clean_exts()
	log.debug("Auto cleanup installed extensions")
	local depends = list_depends()
	for inst, v in pairs(installed) do
		if not depends[inst] then
			remove_depends(inst)
		end
	end
	os.execute('sync')
end

function command.list()
	return installed
end

function command.tasks()
	return tasks
end

function command.install_depends(app_inst)
	local exts = get_app_depends(app_inst)
	local wait_list = {}
	for name, version in pairs(exts) do
		local inst = make_inst_name(name, version)
		if not installed[inst] then
			installed[inst] = {
				name = name,
				version = version,
			}
			wait_list[inst] = {
				task_name = tname,
				running = true,
			}

			create_download(name, version, function(result, info)
				wait_list[inst].result = result
				wait_list[inst].msg = info
				if not result then
					installed[inst] = nil
					log.error(info)
				else
					log.notice("Download Extension finished", name, version)

					local target_folder = get_target_folder(inst)
					lfs.mkdir(target_folder)
					log.debug("tar xzf "..info.." -C "..target_folder)
					local r, status = os.execute("tar xzf "..info.." -C "..target_folder)
					os.execute("rm -rf "..info)
					if r and status == 'exit' then
						install_depends_to_app(inst, app_inst)
					else
						wait_list[inst].result = false
						wait_list[inst].msg = "failed to unzip Extension"
					end
				end
				wait_list[inst].running = false
			end)
		else
			install_depends_to_app(inst, app_inst)
		end
	end

	local t = skynet.now()
	--- max timeout 10 mins
	while (skynet.now() - t) < (10 * 60 * 100) do
		local finished = true
		local result = true
		local info = "done"
		local failed_depends = {}

		for k,v in pairs(wait_list) do
			if v.running then
				finished = false
			end
			if not v.result then
				result = false
				failed_depends[#failed_depends + 1] = k
			end
		end
		if not result then
			info = "Install depends failed, failed exts: "..table.concat(failed_depends)
		end
		if finished then
			return result, info
		end
		skynet.sleep(100)
	end
	return nil, "timeout"
end

function command.upgrade_ext(id, args)
	local inst = args.inst
	local name = args.name
	local version, beta, editor = parse_version_string(args.version)

	--- Stop all applications depends on this extension
	local depends = list_depends()
	local applist = depends[inst]
	local appmgr = snax.uniqueservice("appmgr")
	for _,v in ipairs(applist) do
		appmgr.req.stop(inst, "Upgrade Extension "..inst)
	end

	create_download(name, version, function(result, path)
		if not result then
			log.error("Failed to download extension. Error: "..path)
		else
			log.notice("Download Extension finished", name, version)

			local target_folder = get_target_folder(inst)
			log.debug("tar xzf "..path.." -C "..target_folder)
			local r, status = os.execute("tar xzf "..path.." -C "..target_folder)
			os.execute("rm -rf "..path)
			log.notice("Install Extension finished", name, version, r, status)

			for _,v in ipairs(applist) do
				local r, err = appmgr.req.start(inst)
				if not r then
					log.error("Failed to start application after extension upgraded. Error: "..err)
				end
			end
		end
	end)
end

function command.pkg_check_update(ext, beta)
	local pkg_host = datacenter.get('CLOUD', 'PKG_HOST_URL')
	local beta = beta and datacenter.get('CLOUD', 'USING_BETA')
	local ext = 'ext/'..sysinfo.os_id()..'/'..sysinfo.cpu_arch()..'/'..ext
	return pkg_api.pkg_check_update(pkg_host, ext, beta)
end

function command.pkg_check_version(ext, version)
	local pkg_host = datacenter.get('CLOUD', 'PKG_HOST_URL')
	local ext = 'ext/'..sysinfo.os_id()..'/'..sysinfo.cpu_arch()..'/'..ext
	return pkg_api.pkg_check_version(pkg_host, ext, version)
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
	skynet.register "IOT_EXT"
	installed = list_installed()

	skynet.fork(function()
		while true do
			skynet.sleep(10 * 60 * 100) -- 10 mins
			auto_clean_exts()
		end
	end)
end)

