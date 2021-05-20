local skynet = require 'skynet'
local sm = require('crypt.sm')({})
local basexx = require 'basexx'

local function test()
	local pri_key = '269D0736F3464E16B1E692E6FCDFD57DB2EFF5A9C01F01B72A69DBBE87A5207E'
	local pub_key = 'ADD3C87A7380313971C44B18C31A13B2697FC93E562CA7C5A66863AAC3046E8CC71BF53F16EA2DA6E0ECA08E4AFA702F942ACE1FC110BBE3DCB73BE248F97A53'

	local keyx = string.sub(pub_key, 1, 64)
	local keyy = string.sub(pub_key, 65)

	--[[
	print(sm.sm2key_export(pri_key, keyx, keyy,
	'/tmp/sm2_export.pri.pem', '/tmp/sm2_export.pub.pem'))

	print(sm.sm2pubkey_write(pub_key, '/tmp/sm2_pub_write.pub.pem'))

	print(sm.sm2prikey_write(pri_key, '/tmp/sm2_pri_export.pri.pem'))
	]]--

	print(sm.sm2key_write(	pub_key, '/tmp/sm2_write.pub.pem', 
							pri_key, '/tmp/sm2_write.pri.pem') )

	local srv_key = '99213644F0F7EB64992DAD9AFF59A1215CDFC00F7C620D08646C7537962F8D1A8A1CE9C04F435E5ACF36893BC5BEB81E22A83894847052BD8832EB02A89161BB'

	--print(sm.sm2key_write(srv_key, '/tmp/sm2_srv.pub.pem'))

	print('DONEEEEEEEEEEEEEEEEEEEEEEEEEEE')
end

skynet.start(function()
	print(sm.sm2keygen('/tmp/sm2.pri.pem', '/tmp/sm2.pub.pem'))
	test()
end)
