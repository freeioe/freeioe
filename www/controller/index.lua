return {
	get = function(self)
		--lwf.session.data['user'] = 'aaadddddddddddddddddddddddddddddd'
		--lwf.session:save()
		--lwf.render('view.html', lwf.session.data)
		--
		--ngx.header['aaaa']= 'eee'
		--self.route:json(ngx.req.get_headers())
		lwf.render('view.html', self.context)
	end
}
