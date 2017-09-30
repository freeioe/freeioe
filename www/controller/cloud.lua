local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
		else
			--local cloud = snax.uniqueservice('cloud')
			local cfg = dc.get('CLOUD')
			lwf.render('cloud.html', {cfg=cfg})
		end
	end,
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local action = post.action
		if action == 'enable' then
			local option = post.option
			local info = _("Action is accepted")
			local cloud = snax.uniqueservice('cloud')
			if option == 'data' then
				cloud.post.enable_data(post.enable == 'true')
			elseif option == 'stat' then
				cloud.post.enable_stat(post.enable == 'true')
			elseif option == 'log' then
				cloud.post.enable_log(tonumber(post.enable) or 60)
			elseif option == 'comm' then
				cloud.post.enable_comm(tonumber(post.enable) or 60)
			else
				info = string.format(_("Action %s is not allowed"), option)
			end
			ngx.print(info)
		end
		if action == 'mqtt_host' then
			local host = post.host
			if not host or host == '' then
				host = nil
			end
			dc.set('CLOUD', 'HOST', host)
			ngx.print(_('Cloud host is changed, you need restart system to apply changes!'))
		end
	end
}
