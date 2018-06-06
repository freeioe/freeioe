return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = _("SerialChannel"),
				filename = "ioe/serialchannel.md",
			},
			{
				title = _("SocketChannel"),
				filename = "ioe/socketchannel.md",
			},
			{
				title = _("FT CSV Parser"),
				filename = "ioe/ftcsv.md",
			},
			{
				title = _("INI Parser"),
				filename = "ioe/inifile.md",
			},
			{
				title = _("Cycle Buffer"),
				filename = "ioe/cyclebuffer.md",
			},
			{
				title = _("UUID Module"),
				filename = "ioe/uuid.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs, docs_title=_("FreeIOE System API")})
	end
}
