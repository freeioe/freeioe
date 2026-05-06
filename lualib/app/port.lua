----
-- 这是对freeioe 1162版本及更早版本的修复
-- 因为这些版本的freeioe在进行自我升级时不会删除文件。
-- 此文件应该重命名为 lualib/app/port/init.lua
--

local port = require 'app.port.init'

return port
