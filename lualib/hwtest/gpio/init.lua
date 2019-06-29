local log = require 'utils.log'

local exec = function(cmd)
	log.debug('Exec', cmd)
	return os.execute(cmd)
end

return function (gpio_name, set_un_set, set_check, unset_check)
	local set_str = 'echo 1 > /sys/class/gpio/'..gpio_name..'/value'
	local unset_str = 'echo 0 > /sys/class/gpio/'..gpio_name..'/value'

	if set_un_set then
		log.debug("GPIO_SET_UNSET")
		exec(set_str)
		local r, err = set_check(gpio_name)
		if not r then
			exec(unset_str)
			log.error("GPIO_SET_CHECK failed", err)
			return nil, err
		end
		exec(unset_str)
		r, err = unset_check(gpio_name)
		if not r then
			log.error("GPIO_UNSET_CHECK failed", err)
		end
		return r, err

	else
		log.debug("GPIO_UNSET_SET")
		exec(unset_str)
		local r, err = unset_check(gpio_name)
		if not r then
			log.error("GPIO_UNSET_CHECK failed", err)
			exec(set_str)
			return nil, err	
		end
		exec(set_str)
		r, err = set_check(gpio_name)
		if not r then
			log.error("GPIO_SET_CHECK failed", err)
		end
		return r, err
	end
end
