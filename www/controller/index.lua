return {
	get = function(self)
		--ngx.header['aaaa']= 'eee'
		--self.route:json(ngx.req.get_headers())
		lwf.render('view.html', self.context)
	end
}
