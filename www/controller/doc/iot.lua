return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local filename = get.filename
		local docs = {
			{
				title = "SerialChannel",
				filename = "iot/serialchannel_cn.md",
			},
			{
				title = "SocketChannel",
				filename = "iot/socketchannel_cn.md",
			},
			{
				title = "FT CSV Parser",
				filename = "iot/ftcsv_cn.md",
			},
			{
				title = "INI Parser",
				filename = "iot/inifile_cn.md",
			},
			{
				title = "Cycle Buffer",
				filename = "iot/cyclebuffer_cn.md",
			},
			{
				title = "UUID Module",
				filename = "iot/uuid_cn.md",
			},
		}

		lwf.render("doc.html", {doc=filename, docs=docs})
	end
}
