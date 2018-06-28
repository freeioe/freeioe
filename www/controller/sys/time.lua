local cjson = require 'cjson.safe'

return {
	get = function(self)
		local t = {
			time = os.time(),
			time_str = os.date(),
		}
		ngx.print(cjson.encode(t))
	end,
}
