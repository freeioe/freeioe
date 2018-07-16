return {
	namespace = "urn:unconfigured:application",
	endpoint = "opc.tcp://127.0.0.1:4840", -- Symlink 设备IP
	root_object = "Symlink", --- 根节点ID
	run_sleep = 1000, --- 采集周期
}
