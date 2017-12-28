local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local sysinfo = require 'utils.sysinfo'

local function pretty_memory(size)
	local size = tonumber(size)
	if size > 1024 then
		if size > 1024 * 1024 then
			return math.floor(size / (1024 * 1024))..'G'
		else
			return math.floor(size / 1024)..'M'
		end
	end
	return size
end

local function pretty_time(time)
	local time = tonumber(time)
	local tsec = time % 60
	local tmin = math.floor((time % 3600) / 60) or 0
	local thour = math.floor((time % (3600 * 24)) / 3600) or 0
	local tday = math.floor(time / (3600 * 24)) or 0
	local t = nil
	if t or tday ~= 0 then
		t = tday.." "
	end
	if t or thour ~= 0 then
		t = (t or "")..thour..":"
	end
	if t or tmin ~= 0 then
		t = (t or "")..tmin..":"
	end
	t = (t or "")..tsec
	return t
end

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end
		local get = ngx.req.get_uri_args()
		local ver, git_ver = sysinfo.version()
		local sver, git_sver = sysinfo.skynet_version()
		local version = {
			iot = {
				ver = ver,
				git_ver = git_ver,
			},
			skynet = {
				ver = sver,
				git_ver = git_sver,
			},
		}
		local cpu_model = sysinfo.cpu_model()
		local meminfo =  sysinfo.meminfo()
		local uname = sysinfo.uname("-a")
		local rollback_time = skynet.call("UPGRADER", "lua", "rollback_time")
		local arch = sysinfo.cpu_arch()
		local os_id = sysinfo.os_id()
		local using_beta = dc.get('CLOUD', 'USING_BETA')
		
		local cloud = snax.uniqueservice('cloud')
		local cloud_status, cloud_last = cloud.req.get_status()
		--cloud_last = pretty_time(math.floor(skynet.time() - cloud_last))
		cloud_last = math.floor(cloud_last)
		local uptime = string.match(sysinfo.exec('cat /proc/uptime') or "", "%d+")
		local uptime_str = sysinfo.exec('uptime -s')

		lwf.render('dashboard.html', {
			version = version, 
			cpu_model = cpu_model,
			mem_info= {
				total = pretty_memory(meminfo.total),
				used = pretty_memory(meminfo.used),
				free = pretty_memory(meminfo.free),
			}, 
			uname = uname,
			rollback_time = rollback_time,
			cpu_arch = arch,
			os_id = os_id,
			using_beta = using_beta,
			force_upgrade = get.force_upgrade,
			cloud_status = cloud_status,
			cloud_last = cloud_last,
			uptime = uptime,
			uptime_str = uptime_str,
		})
	end
}
