return {
	get = function(self)
		local get, post, files = lwf.reqargs()
		for k,v in pairs(get) do print(k,v) end
		lwf.json(self, get)
	end,
	post = function(self)
		local get, post, files = lwf.reqargs()
		for k,v in pairs(get) do print(k,v) end
		print('-----------')
		for k,v in pairs(post) do print(k,v) end
		lwf.json(self, post)
	end,
}
