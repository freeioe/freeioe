return {
	get = function(self)
		local get, post, files = lwf.reqargs()
		for k,v in pairs(get) do print(k,v) end
		lwf.json(self, get)
	end
}
