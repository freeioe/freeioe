
return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local fn = get.filename
		print(fn)
		local f, err = io.open(ngx.var.document_root.."/../assets/doc/"..fn, "r")
		if not f then
			return ""
		end
		local str = f:read('a')
		f:close()
		ngx.header.content_type = "text/plain; charset=utf-8"
		ngx.print(str)
	end,
}
