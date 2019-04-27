local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local lfs = require 'lfs'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
		else
			local get = ngx.req.get_uri_args()
			--local cloud = snax.queryservice('cloud')
			local cfg = dc.get('CLOUD')
			local sys = dc.get('SYS')
			local edit_sn = lfs.attributes("/etc/profile.d/echo_sn.sh", "mode") == 'file'
			lwf.render('cloud.html', {sys=sys, cfg=cfg, nowtime=skynet.time(), edit_enable=get.edit_enable, edit_sn=edit_sn})
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
			local id = 'from_web'
			local cloud = snax.queryservice('cloud')
			if option == 'data' then
				--print(option, post.enable=='true')
				cloud.post.enable_data(id, post.enable == 'true')
			elseif option == 'stat' then
				--print(option, post.enable=='true')
				cloud.post.enable_stat(id, post.enable == 'true')
			elseif option == 'cache' then
				cloud.post.enable_cache(id, post.enable == 'true')
			elseif option == 'log' then
				--print(option, tonumber(post.enable) or 0)
				cloud.post.enable_log(id, tonumber(post.enable) or 0)
			elseif option == 'comm' then
				--print(option, tonumber(post.enable) or 0)
				cloud.post.enable_comm(id, tonumber(post.enable) or 0)
			elseif option == 'event' then
				cloud.post.enable_event(id, tonumber(post.enable) or -1)
			else
				info = _("Action %s is not allowed", option)
			end
			ngx.print(info)
		end
		if action == 'cloud' or action == 'mqtt' then
			local option = post.option
			local value = post.value
			if string.upper(option) == 'DATA_UPLOAD_PERIOD' then
				value = math.floor(tonumber(value))
				if value > 0 and value < 1000 then
					return ngx.print(_('The upload period cannot be less than 1000 ms (one second)'))
				end
			end
			if string.upper(option) == 'COV_TTL' then
				value = math.floor(tonumber(value))
				if value < 60 then
					return ngx.print(_('The COV TTL cannot be less than 60 seconds'))
				end
			end
			if string.upper(option) == 'ID' then
				if string.len(tostring(value) or '') == 0 then
					value = nil
				end
			end
			if string.upper(option) == 'DATA_CACHE_PER_FILE' then
				value = math.abs(math.floor(tonumber(value)))
				if value < 1024 then
					return ngx.print(_('The Data Cache Per File cannot be less than 1024'))
				end
			end
			if string.upper(option) == 'DATA_CACHE_LIMIT' then
				value = math.abs(math.floor(tonumber(value)))
				if value > 4096  then
					return ngx.print(_('The Data Cache File count limit cannot more than 4096'))
				end
			end
			if string.upper(option) == 'DATA_CACHE_FIRE_FREQ' then
				value = math.abs(math.floor(tonumber(value)))
				if value < 1000  then
					return ngx.print(_('The Data Cache Fire Freq cannot more than 1000 ms'))
				end
			end

			--print(option, value)
			dc.set('CLOUD', string.upper(option), value)
			ngx.print(_('Cloud option is changed, you need restart FreeIOE to apply changes!'))
		end
	end
}
