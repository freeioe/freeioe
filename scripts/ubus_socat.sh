
while [ 1 ]
do
	sleep 1
	echo "Start UBUS Link"
	# socat tcp-connect:172.30.19.103:11000 unix-listen:/var/run/ubus.sock 
	socat tcp-connect:172.30.11.230:11000 unix-listen:/tmp/ubus.sock
done
