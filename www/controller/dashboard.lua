local sysinfo = require 'utils.sysinfo'

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

		lwf.render('dashboard.html', {
			version = version, 
			cpu_model = cpu_model,
			mem_info= {
				total = math.floor(meminfo.total / 1024)..'M',
				used = math.floor(meminfo.used / 1024)..'M',
				free = math.floor(meminfo.free / 1024)..'M',
			}, 
			uname = uname,
		})
	end
}
