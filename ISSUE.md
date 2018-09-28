1. After started the process-monitor to watching frpc, the os.execute('cat /proc/loadavg') will be blocked. The shell started by os.execute is in Z status in ps list. (it was happened in openwrt x86_64 image with vmware)  --- It possibly bug of musl in x86_64 in virtual machine, we switch to use libc in x86_64
2. 
