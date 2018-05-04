local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			lwf.render('event.html')
		end
	end
}
