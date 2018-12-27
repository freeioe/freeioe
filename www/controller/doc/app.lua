return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = _("SYS"),
				filename = "app/sys.md",
			},
			{
				title = _("API"),
				filename = "app/api.md",
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
			{
				title = _("EVENT"),
				filename = "app/event.md",
			},
			{
				title = _("CONF_API"),
				filename = "app/conf_api.md",
			},
			{
				title = _("CONF_HELPER"),
				filename = "app/conf_helper.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs, docs_title=_("Application API")})
	end
}
