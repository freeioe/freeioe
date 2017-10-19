local skynet = require 'skynet'
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

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end
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
		local plat = sysinfo.skynet_platform()
		local using_beta = dc.get('CLOUD', 'USING_BETA')

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
			platform = plat,
			using_beta = using_beta,
		})
	end
}
