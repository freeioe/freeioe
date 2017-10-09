return {
	get = function(self)
		lwf.render('user/profile.html', {user=lwf.auth.user})
	end,
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local action = post.action
		local passwd = post.passwd
		local repass = post.repass
		if passwd == repass then
			lwf.auth:update_password(passwd)
			ngx.print(_("Password updated!!"))
		else
			ngx.print(_("Password Retyped Incorrect!"))
		end
	end,
}
