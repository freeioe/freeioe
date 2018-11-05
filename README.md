FreeIOE
===================

[FreeIOE](http://freeioe.org) is an framework for building IOE (Internet Of Everything) gateway device.

[Chinese|中文](https://github.com/freeioe/freeioe/README_CN.md)


## How to use FreeIOE devices

[Guick Guide](https://help.cloud.thingsroot.com) Quick start guide (only in Chinese for now).

[ThingsRoot Cloud](http://cloud.thingsroot.com) is default cloud provider for FreeIOE.

[FreeIOE forum](http://freeioe.org) is the discussion forum.


## How to develop application for FreeIOE

### Application API document

[Application API Book](https://github.com/srdgame/iot_app_api_book) currently only in Chinese.


### Application examples

[FreeIOE Example Applications](https://github.com/freeioe/freeioe_example_apps)

This repo provides few example applications, includes:

* Modbus application with lua-modbus(libmodbus)
* Modbus application implemented in pure lua
* OpcUA Server/Client applications
* Socat/Frpc utils control applications
* Aliyun/Huawei/Baidu IOT cloud application (based on MQTT)
* DLT645 application implemented in pure lua
* Device network configuration application (based on uci)
* SymLink connector with OpcUA


## FreeIOE core development

FreeIOE is based on [Skynet](https://github.com/cloudwu/skynet). More information can be found in its Wiki [Skynet Wiki](https://github.com/cloudwu/skynet/wiki)


## Report bugs

Please use [issue list](https://github.com/freeioe/freeioe/issues).


## Where to buy FreeIOE device

[ThingsRoot](https://thingsroot.com/product/)


## Known Issue

* FreeIOE upgradation will not remove original files.
> 1. the delete files from new package will retain in local
> 2. cannot have file(soft link file) replace directory
