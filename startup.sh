#!/bin/sh

IOT_DIR=$1
START_TIME_FILE=/tmp/iot_start_time.txt
STARTUP_LOG=/tmp/iot_startup.log

date > $START_TIME_FILE
date +%s >> $START_TIME_FILE

echo "Starting...." > $STARTUP_LOG
date +"Start Time: %c" >> $STARTUP_LOG

if [ -f $IOT_DIR/ipt/upgrade.sh ]
then
	echo "Upgrade Script detected! Upgrade iot system!" >> $STARTUP_LOG
	sh $IOT_DIR/ipt/upgrade.sh
	if [ $? -eq 0 ]
		mv -f $IOT_DIR/ipt/upgrade.sh $IOT_DIR/ipt/upgrade.sh.bak
	then
		echo "Failed to run upgrage script" >> $STARTUP_LOG
		exit $?
	fi
fi

if [ -f $IOT_DIR/ipt/rollback.sh ]
then
	echo "RollBack Script detected! Roll back iot system!" >> $STARTUP_LOG
	sh $IOT_DIR/ipt/rollback.sh
	if [ $? -eq 0 ]
		mv -f $IOT_DIR/ipt/rollback.sh $IOT_DIR/ipt/rollback.sh.bak
	then
		echo "Failed to run rollback script" >> $STARTUP_LOG
		exit $?
	fi
fi

echo "Startup Script Done!" >> $STARTUP_LOG
