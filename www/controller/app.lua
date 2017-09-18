local dc = require 'skynet.datacenter'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			lwf.redirect('/user/login')
		else
			local apps = dc.get('APPS')
			lwf.render('app.html', {apps=apps})
		end
	end
}
