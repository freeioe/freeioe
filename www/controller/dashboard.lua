local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
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

		lwf.render('dashboard.html', {version = version})
	end
}
