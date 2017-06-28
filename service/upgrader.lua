local skynet = require "skynet.manager"
local httpdown = require "httpdown"
local log = require 'utils.log'
local lfs = require 'lfs'

local tasks = {}
local command = {}
local conf = {
	host = "cloud.symgrid.cn",
	port = 8000,
}

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
			log.error("Failed to create temp file. Error: "..err)
			return cb(nil, err)
		end
		local status, header, body = httpdown.get(conf.host, "/download_app", {}, {app=app_name})
		if not status then
			log.error("Failed download app, error: "..header)
			return cb(nil, header)
		end
		file:write(body)
		file:close()
		cb(true, fn)
	end
	create_task(down, "Download App "..app_name)
end

function command.upgrade_app(inst_name)
	create_task(function()
		print("XXXXXXXXXX")
		skynet.sleep(10000)
	end, "Upgrade App "..inst_name)
end

function command.install_app(name, version, inst_name)
	local inst_name = inst_name
	local target_folder = get_target_folder(inst_name)
	lfs.mkdir(target_folder)

	create_download(name, version, function(r, path)
		if r then
			os.execute("unzip "..path.." -d "..target_folder)
			appmgr.start(inst_name, {})
		end
	end)
end

function command.uninstall_app(inst_name)
	local appmgr = snax.uniqueservice("appmgr")
	local target_folder = get_target_folder(inst_name)

	local r, err = appmgr.stop(inst_name, "Uninstall App")
	if r then
		os.execute("rm -rf "..target_folder)
	end
end

function command.upgrade_core(version)
	create_download('iot', version, function(r, path)
		if r then
			os.execute("unzip "..path.." -d "..target_folder)
		end
	end)
end

function command.list()
	return tasks
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register "UPGRADER"
end)

