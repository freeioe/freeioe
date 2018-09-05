local sysinfo = require 'utils.sysinfo'
local ioe = require 'ioe'

return {
	get = function(self)
		local ver, git_ver = sysinfo.version()
		local sver, git_sver = sysinfo.skynet_version()
		local cpu_model = sysinfo.cpu_model()
		local uname = sysinfo.uname("-a")
		local arch = sysinfo.cpu_arch()
		local os_id = sysinfo.os_id()
		local using_beta = ioe.beta()
		local ioe_sn = ioe.hw_id()
		local uptime = string.match(sysinfo.cat_file('/proc/uptime') or "", "%d+")
		local uptime_str = sysinfo.exec('uptime -s')
		lwf.json(self, {
			version = version, 
			cpu_model = cpu_model,
			uname = uname,
			cpu_arch = arch,
			os_id = os_id,
			ioe_sn = ioe_sn,
			using_beta = using_beta,
			uptime = uptime,
			uptime_str = uptime_str,
		})
	end
}
