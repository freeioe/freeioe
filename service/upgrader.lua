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
		return install_result(id, false, "Failed to install App. Error: "..err)
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
				return install_result(id, true, "Application installtion is done")
			else
				datacenter.set("APPS", inst_name, nil)
				os.execute("rm -rf "..target_folder)
				return install_result(id, false, "Failed to start App. Error: "..err)
			end
		else
			return install_result(id, false, "Failed to download App. Error: "..info)
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
		return install_result(id, true, "Application uninstall is done")
	else
		return install_result(id, false, "Application uninstall failed, Error: "..err)
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
			return install_result(id, false, "Failed to download App. Error: "..info)
		end
	end, ".tar.gz")

end

local function get_ps_e()
	local r, status, code = os.execute("ps -e > /dev/null")
	if not r then
		return "ps"
	end
	return "ps -e"
end

local upgrade_sh_str = [[
#!/bin/sh

IOT_DIR=%s
SKYNET_FILE=%s
SKYNET_PATH=%s
SKYNET_IOT_FILE=%s
SKYNET_IOT_PATH=%s

date > $IOT_DIR/ipt/rollback

cd $IOT_DIR
if [ -f $SKYNET_FILE ]
then
	cd $SKYNET_PATH
	tar xzf $SKYNET_FILE

	if [ $? -eq 0 ]
	then
		mv -f $SKYNET_FILE $IOT_DIR/ipt/skynet.tar.gz.new
	else
		echo "tar got error!"
		exit $?
	fi
fi

cd "$IOT_DIR"
if [ -f $SKYNET_IOT_FILE ]
then
	cd $SKYNET_IOT_PATH
	tar xzf $SKYNET_IOT_FILE

	if [ $? -eq 0 ]
	then
		mv -f $SKYNET_IOT_FILE $IOT_DIR/ipt/skynet_iot.tar.gz.new
	else
		echo "tar got error!"
		exit $?
	fi
fi

if [ -f $IOT_DIR/ipt/upgrade_need_ack ]
then
	rm -f $IOT_DIR/ipt/upgrade_need_ack
else
	rm -f $IOT_DIR/ipt/rollback
	mv -f $IOT_DIR/ipt/rollback.sh.new $IOT_DIR/ipt/rollback.sh
	if [ -f $IOT_DIR/ipt/skynet.tar.gz.new ] 
	then
		mv -f $IOT_DIR/ipt/skynet.tar.gz.new $IOT_DIR/ipt/skynet.tar.gz
	fi
	mv -f $IOT_DIR/ipt/skynet_iot.tar.gz.new $IOT_DIR/ipt/skynet.tar.gz
fi

]]

local rollback_sh_str = [[
#!/bin/sh

IOT_DIR=%s
SKYNET_PATH=%s
SKYNET_IOT_PATH=%s

cd $IOT_DIR
cd $SKYNET_PATH
tar xzf $IOT_DIR/ipt/skynet.tar.gz

cd $IOT_DIR
cd $SKYNET_IOT_PATH
tar xzf $IOT_DIR/ipt/skynet_iot.tar.gz
]]

local upgrade_ack_sh_str = [[
#!/bin/sh

IOT_DIR=%s

mv -f $IOT_DIR/ipt/skynet.tar.gz.new $IOT_DIR/ipt/skynet.tar.gz
mv -f $IOT_DIR/ipt/skynet_iot.tar.gz.new $IOT_DIR/ipt/skynet_iot.tar.gz
mv -f $IOT_DIR/ipt/rollback.sh.new $IOT_DIR/ipt/rollback.sh
rm -f $IOT_DIR/ipt/rollback

]]

local function get_iot_dir()
	return os.getenv('IOT_DIR') or lfs.currentdir().."/.."
end

local function write_script(fn, str)
	local f, err = io.open(fn, "w+")
	if not f then
		return nil, err
	end
	f:write(str)
	f:close()
	return true
end

local function start_upgrade_proc(iot_path, skynet_path)
	assert(iot_path)
	log.warning("Core System Upgrade....")
	log.trace(iot_path, skynet_path)
	--local ps_e = get_ps_e()

	local base_dir = get_iot_dir()
	lfs.mkdir(base_dir.."/ipt")
	local str = string.format(rollback_sh_str, base_dir, "skynet", "skynet_iot")
	local r, err = write_script(base_dir.."/ipt/rollback.sh.new", str)
	if not r then
		return false, err
	end

	local str = string.format(upgrade_ack_sh_str, base_dir)
	local r, err = write_script(base_dir.."/ipt/upgrade_ack.sh", str)
	if not r then
		return false, err
	end

	local str = string.format(upgrade_sh_str, base_dir, skynet_path, "skynet", iot_path, "skynet_iot")
	local r, err = write_script(base_dir.."/ipt/upgrade.sh", str)
	if not r then
		return false, err
	end
	write_script(base_dir.."/ipt/upgrade", os.date())

	skynet.timeout(50, function()
		skynet.abort()
	end)

	log.warning("Core System Upgration Done!")
	return true, "Upgration is done!"
end

function command.upgrade_core(id, args)
	local is_windows = package.config:sub(1,1) == '\\'
	local version = args.version or 'latest'
	local md5 = args.md5
	local skynet = args.skynet

	if args.ack then
		local base_dir = get_iot_dir()
		local r, status, code = os.execute("date > "..base_dir.."/ipt/upgrade_need_ack")
		if not r then
			return install_result(id, false, "Failed to create upgrade_need_ack file!")
		end
	end

	create_download('skynet_iot', version, md5, function(r, info)
		if r then
			if skynet then
				download_upgrade_skynet(id, skynet, function(path) 
					local r, err = start_upgrade_proc(info, path) 
					return install_result(id, r, err)
				end)
			else
				local r, err = start_upgrade_proc(path)
				return install_result(id, r, err)
			end
		else
			return install_result(id, false, "Failed to download App. Error: "..info)
		end
	end, ".tar.gz")
end

function command.upgrade_core_ack(id, args)
	local base_dir = get_iot_dir()
	local upgrade_ack_sh = base_dir.."/ipt/upgrade_ack.sh"
	local r, status, code = os.execute("sh "..upgrade_ack_sh)
	if not r then
		return install_result(id, false, "Failed execute ugprade_ack.sh.  "..status.." "..code)
	end
	return install_result(id, true, "Upgration ACK is done")
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

