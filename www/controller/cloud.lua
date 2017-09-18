local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			lwf.redirect('/user/login')
		else
			--local cloud = snax.uniqueservice('cloud')
			local cfg = dc.get('CLOUD')
			lwf.render('cloud.html', {cfg=cfg})
		end
	end,
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
	end
}
