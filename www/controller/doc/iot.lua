return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = _("SerialChannel"),
				filename = "iot/serialchannel_cn.md",
			},
			{
				title = _("SocketChannel"),
				filename = "iot/socketchannel_cn.md",
			},
			{
				title = _("FT CSV Parser"),
				filename = "iot/ftcsv_cn.md",
			},
			{
				title = _("INI Parser"),
				filename = "iot/inifile_cn.md",
			},
			{
				title = _("Cycle Buffer"),
				filename = "iot/cyclebuffer_cn.md",
			},
			{
				title = _("UUID Module"),
				filename = "iot/uuid_cn.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs, docs_title=_("IOT System API")})
	end
}
