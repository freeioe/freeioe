
return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
		else
			lwf.render('batch_script.html')
		end
	end
}
