return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = _("API"),
				filename = "app/api.md",
			},
			{
				title = _("SYS"),
				filename = "app/sys.md",
			},
			{
				title = _("DEVICE"),
				filename = "app/device.md",
			},
			{
				title = _("STAT"),
				filename = "app/stat.md",
			},
			{
				title = _("LOGGER"),
				filename = "app/logger.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs, docs_title=_("Application API")})
	end
}
