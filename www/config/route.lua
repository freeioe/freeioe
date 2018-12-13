
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

route('#/snax/(.+)', function(self, snax_path)
	if lwf.auth.user == 'Guest' then
		self:redirect('/user/login')
		return router:exit(401)
	end
	-- call snax service
	local snax_name, snax_method = string.match(snax_path, '^[^/]+/([^/]+)$')
	if not snax_name or not snax_method then
		return router:exit(404)
	end

	local snax = require 'skynet.snax'
	local cjson = require 'cjson.safe'

	local snax_s = snax.queryservice(snax_name)
	if not snax_s or not snax_s.req[snax_method] then
		return router:exit(404)
	end

	local method = lwf.var.method
	if method ~= "GET" and method ~= "HEAD" then
		return router:exit(405)
	end
	local params = {}
	if method == 'GET' then
		local args = ngx.req.get_uri_args()
		params = cjson.decode(args.params) or {}
	else
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		params = cjson.decode(post.params) or {}
	end

	local data, err = snax_s.req[snax_method](table.unpack(params))
	if not data then
		return router:exit(500, err)
	end

	ngx.header.content_type = "application/json; charset=utf-8"
	ngx.print(cjson.encode(data))
end)
