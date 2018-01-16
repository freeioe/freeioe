local skynet = require 'skynet.manager'
local datacenter = require 'skynet.datacenter'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local httpdown = require 'httpdown'
local pkg_api = require 'pkg_api'
local lfs = require 'lfs'

local tasks = {}
local installed = {}
local command = {}

local function get_target_root()
	return lfs.currentdir().."/iot/ext/"
end

local function get_app_target_folder(inst_name)
	return lfs.currentdir().."/iot/apps/"..inst_name.."/"
end

local function get_target_folder(inst_name)
	return lfs.currentdir().."/iot/ext/"..inst_name.."/"
end

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
	return true, task_name
end

local function create_download(plat, app_name, version, cb)
	local app_name = app_name:gsub('%.', '/')
	local cb = cb
	local ext = ".tar.gz"
	local down = function()
		local app_name_escape = string.gsub(app_name, '/', '__')
		local path = "/tmp/"..app_name_escape.."_"..version..ext
		local file, err = io.open(path, "w+")
		if not file then
			return cb(nil, err)
		end

		local pkg_host = datacenter.get("CLOUD", "PKG_HOST_URL")

		local url = "/download/ext/"..plat.."/"..app_name.."/"..version..ext
		log.notice('Start Download Ext', app_name, 'From URL:', pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return cb(nil, tostring(header))
		end
		if status < 200 or status > 400 then
			return cb(nil, "Download Ext failed, status code "..status)
		end
		file:write(body)
		file:close()

		local status, header, body = httpdown.get(pkg_host, url..".md5")
		if status and status == 200 then
			local sum, err = helper.md5sum(path)
			if not sum then
				return cb(nil, "Cannot caculate md5, error:\t"..err)
			end
			log.notice("Downloaded file md5 sum", sum)
			local md5, cf = body:match('^(%w+)[^%g]+(.+)$')
			if sum ~= md5 then
				return cb(nil, "Check md5 sum failed, expected:\t"..md5.."\t Got:\t"..sum)
			end
		end
		cb(true, path)
	end
	create_task(down, "Download Ext "..app_name)
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
	os.execute('sync')
end

local function install_depends_to_app(ext_inst, app_inst)
	log.debug("Try to install "..ext_inst.." to "..app_inst)
	install_depends_to_app_ext(ext_inst, app_inst, 'luaclib')
	install_depends_to_app_ext(ext_inst, app_inst, 'bin')
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

			local plat = sysinfo.os_id()..'/'..sysinfo.cpu_arch()

			create_download(plat, name, version, function(result, info)
				wait_list[inst].result = result
				wait_list[inst].msg = info
				if not result then
					installed[inst] = nil
					log.error(info)
				else
					log.notice("Download Ext finished", name, version)

					local target_folder = get_target_folder(inst)
					lfs.mkdir(target_folder)
					log.debug("tar xzf "..info.." -C "..target_folder)
					local r, status = os.execute("tar xzf "..info.." -C "..target_folder)
					os.execute("rm -rf "..info)
					if r and status == 'exit' then
						install_depends_to_app(inst, app_inst)
					else
						wait_list[inst].result = false
						wait_list[inst].msg = "failed to unzip Ext"
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

function remove_depends(inst)
	log.warning('Remove Ext', inst)
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
				log.debug('Installed Ext', name, version)
				list[filename] = {
					name = name,
					version = version
				}
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
	log.notice("Auto cleanup installed extensions")
	local depends = list_depends()
	for inst, v in pairs(installed) do
		if not depends[inst] then
			remove_depends(inst)
		end
	end
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

