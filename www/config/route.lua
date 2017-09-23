
route("=*/help", function(self)
	lwf.render("help.html", {})
end)

route('#/lang/(.+)', function(self, lang)
	lwf.session.data.lang = lang or 'zh_CN'
	lwf.session:save()
	self:redirect('/')
end)

--[[
route('#/zh/(.+)', function(self, url)
	ngx.header['Accpet-Language'] = 'zh_CN'
	self:exec(url, {})
end)
]]--

