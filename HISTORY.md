
---

# Release history

v1.8.1 (2020-08-05)
------------------

* Support PPP mode in home-made openwrt hardwares
* Fixed missing stop bits function in serialdriver
* Improve the self-upgrade process
* Support strip_mode
* Fixed df asserts on BMT devices


v1.8.0 (2020-04-13)
------------------

* Fixed the MQTT based application data been fired twice issue
* Using the FreeIOE web admin password for reboot hack


v1.7.3 (2020-03-06)
------------------

* Fixed the connection lost message
* Fixed the data has been fire twice in MQTT apps


v1.7.2 (2019-12-24)
------------------

* Fixed conf.json file missing assert


v1.7.1 (2019-12-10)
------------------

* Remove the rc<n> version postfix (openwrt)
* Support 'never' time span in summation
* Using time counter for standby battery working status
* Fixed summation asserts with empty saving file (file lost?)
* Fixed the event type fired in appmgr 


v1.7.0 (2019-11-06)
------------------

* Removed the embedded document
* Added compat folder
* Show cloud information in ubus interface


v1.6.4 (2019-10-23)
------------------

* API_VER is 6 now
* Added utils.timer module
* Improved summation module
* Show more tips on API_VER error
* Refine the log content
* Backup the configuration and try to restore it when error found


v1.6.3 (2019-09-20)
------------------

* Fixed application serial number not updated when rename instance name
* Echo the data compress rate every 60 seconds
* Improve the period buffer sleep length
* Show the error information when failed to parse app's conf.json file
* Fixed application delete with error will not cleanup the devices stuff
* Increase the app hearbeat time to avoid MQTT killed caused by connection timeout
* Support device reboot hack


v1.6.2 (2019-09-17)
------------------

* Fixed ubus failure on method not found case
* Support disable Symlink via FreeIOE
* Support insecure tls mqtt connection


v1.6.1 (2019-08-29)
------------------

* Fixed MQTT base app fires twice message when from on_connection_ok
* Echo cloud status to /tmp/sysinfo/cloud_status


v1.6.0 (2019-08-19)
------------------

* Support ThingsLink T1 3000 (CSQ leds are controled by wwanleds)
* Support ThingsLink Q204 (ccid cspi not working for now)
* Support OS version in boot script
* Application base module support on_init for object initialization
* Halt device when hardware test finished, and blink leds when failed
* Fixed LTE WAN does not been reported if 3ginfo does not genereated issue
* Ask all application to quit before restart FreeIOE
* Fixed the app.utils.calc do not handle the value quality correctly issue
* Fixed summation utils count the value incorrect when value reseted (base is not zero) 
* Support application reading default settings from its visual config file (API version 5)


v1.5.0 (2019-08-01)
------------------

* Using OS/Version/CPU_ARCH for platform information
* Fixed serial port closes issue
* Changed default device meta manufactor to FreeIOE
* Support upgrade skynet code without freeioe
* Support script application configuration in batch script
* Support device shared between application with specified secret



v1.4.5 (2019-07-10)
------------------

* Fixed application configuration cannot be changed from cloud


v1.4.4 (2019-07-10)
------------------

* Fixed application will be restart more than one times when heartbeat timeout
* Fixed application auto start will be reset when upgrade application


v1.4.3 (2019-07-09)
------------------

* Added limitation for the application instance name
* Support automatic value type conversion
* Fixed mqtt base application module
* Added hardware tests modules for ThingsLink X1
* Added GPIO control utils which similar as LEDS control utils module
* Improve application release script
* Support Q204


v1.4.2 (2019-06-06)
------------------

* Fixed typo (mounts)


v1.4.1 (2019-06-03)
------------------

* Fixed empty string instance name issue


v1.4.0 (2019-5-29)
------------------

* Support cache data into file when mqtt connection is down.
* Fix system time by added skynet.fix_time instead of restart
* Limit the max data per packet in data upload
* Command/Output/Ctrl result post to source application
* Handle MQTT QOS message
* Improve the app.port modules
* Fixed event type missing


v1.3.4 (2019-4-24)
------------------

* Ergent fix about device serial number validation.


v1.3.3 (2019-4-24)
------------------

* Fixed cov assets in application calculation utility helper
* Added unit for ioe device


v1.3.2 (2019-4-22)
------------------

* Flush data when period buffer enabled with longer period
* Fixed query data takes too much time issue
* Delay gcom reading as it takes too much time (app.ioe)
* Fixed COV TTL issue
* Force data flush when offline more than 60 seconds
* Echo cloud information to /tmp/sysinfo folder
* Create mqtt app helper
* Improved COV and PeriodBuffer
* Fixed mod_device will cleanup all device information
* Cleanup input/output from datacenter when device removed
* Create application calculation utility helper
* Increate application api version to four(4)


v1.3.1 (2019-1-10)
------------------

* Fixed upgrade failure issue.


v1.3.0 (2019-1-10)
------------------

* Make the web pages be optional
* Fixed event upload level missing
* Fixed app.run called after app.close
* New package name principle for application
* A few version information in FreeIOE device meta
* App API version 3, support COV on device object


v1.2.3 (2018-12-26)
------------------

* Improve ubus service
* Fixed app create event assert
* Added log prefix for all services and apps
* Added more reserved app instance names for log prefix
* Support download application via websocket (VSCode extension)
* Fixed local appliation install from web
* Fixed set configuration from web does not apply to app inst
* Fixed data one short will disable data upload


v1.2.2 (2018-12-11)
------------------

* Fixed ubus detection


v1.2.1 (2018-12-10)
------------------
* Fixed ubus call parameter issue


v1.2.0 (2018-12-10)
------------------

* Support ubus based on lsocket
* Create ubus service when OS is OpenWRT
* Upload data within one second when connected to cloud


v1.1.2 (2018-11-23)
------------------

* Emergency input value (API\_VER=2)
* Force kill application if timeout
* Control signal stength led
* Support rename app instance name
* Support pack app from websocket
* Upgrade with latest skynet
* Improving upgrader and ioe\_ext service
* Bug fixes


v1.1.1 (2018-9-25)
------------------

* Fixed beta flag reading issue
* Reading system firmware/os version
* Migrate cloud host to thingsroot.com


v1.1.0 (2018-9-11)
------------------

* Support VS Code extension with WebSocket
* Fixed a few bugs


v1.0.1 (2018-8-8)
-----------
* Fixed devices data infinitely.
* Improved serial driver/channel.


v1.0.0 (2018-8-1)
------------------

* First release version.

