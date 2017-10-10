return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = _("SerialChannel"),
				filename = "iot/serialchannel.md",
			},
			{
				title = _("SocketChannel"),
				filename = "iot/socketchannel.md",
			},
			{
				title = _("FT CSV Parser"),
				filename = "iot/ftcsv.md",
			},
			{
				title = _("INI Parser"),
				filename = "iot/inifile.md",
			},
			{
				title = _("Cycle Buffer"),
				filename = "iot/cyclebuffer.md",
			},
			{
				title = _("UUID Module"),
				filename = "iot/uuid.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs, docs_title=_("IOT System API")})
	end
}
