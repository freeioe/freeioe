----
-- This is an fix for freeioe version older than 1162
-- As those versions of freeioe will not remove files when do
-- self-upgrade.  AND we have this file which should be rename 
-- to lualib/app/port/init.lua
--

local port = require 'app.port.init'

return port
