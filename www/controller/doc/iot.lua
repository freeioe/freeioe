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
		}

		lwf.render("doc.html", {doc=filename, docs=docs})
	end
}
