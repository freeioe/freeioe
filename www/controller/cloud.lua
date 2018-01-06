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
			lwf.render('cloud.html', {cfg=cfg, nowtime=skynet.time()})
		end
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local action = post.action
		if action == 'enable' then
			local option = post.option
			local info = _("Action is accepted")
			local cloud = snax.uniqueservice('cloud')
			if option == 'data' then
				--print(option, post.enable=='true')
				cloud.post.enable_data(post.enable == 'true')
			elseif option == 'stat' then
				--print(option, post.enable=='true')
				cloud.post.enable_stat(post.enable == 'true')
			elseif option == 'log' then
				--print(option, tonumber(post.enable) or 0)
				cloud.post.enable_log(tonumber(post.enable) or 0)
			elseif option == 'comm' then
				--print(option, tonumber(post.enable) or 0)
				cloud.post.enable_comm(tonumber(post.enable) or 0)
			else
				info = string.format(_("Action %s is not allowed"), option)
			end
			ngx.print(info)
		end
		if action == 'mqtt' then
			local option = post.option
			local value = post.value
			print(option, value)
			dc.set('CLOUD', string.upper(option), value)
			ngx.print(_('Cloud option is changed, you need restart system to apply changes!'))
		end
	end
}
