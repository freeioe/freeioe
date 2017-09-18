return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			lwf.redirect('/user/login')
		else
			lwf.render('settings.html')
		end
	end
}
