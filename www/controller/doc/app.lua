return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = "API",
				filename = "app/api_cn.md",
			},
			{
				title = "SYS",
				filename = "app/sys_cn.md",
			},
			{
				title = "DEVICE",
				filename = "app/device_cn.md",
			},
			{
				title = "STAT",
				filename = "app/stat_cn.md",
			},
			{
				title = "LOGGER",
				filename = "app/logger_cn.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs})
	end
}
