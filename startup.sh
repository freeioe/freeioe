#!/bin/sh

IOT_DIR=$1
START_TIME_FILE=/tmp/iot_start_time.txt
STARTUP_LOG=/tmp/iot_startup.log

cd $IOT_DIR

date > $START_TIME_FILE
date +%s >> $START_TIME_FILE

echo "Starting...." > $STARTUP_LOG
date +"Start Time: %c" >> $STARTUP_LOG

if [ -f $IOT_DIR/ipt/upgrade ]
then
	echo "Upgrade Script detected! Upgrade iot system!" >> $STARTUP_LOG
	sh $IOT_DIR/ipt/upgrade.sh
	if [ $? -eq 0 ]
		rm -f $IOT_DIR/ipt/upgrade
	then
		echo "Failed to run upgrage script" >> $STARTUP_LOG
		exit $?
	fi
else
	echo "NO upgrade needed!" >> $STARTUP_LOG
fi

if [ -f $IOT_DIR/ipt/rollback ]
then
	echo "RollBack Script detected! Roll back iot system!" >> $STARTUP_LOG
	sh $IOT_DIR/ipt/rollback.sh
	if [ $? -eq 0 ]
		rm -f $IOT_DIR/ipt/rollback
	then
		echo "Failed to run rollback script" >> $STARTUP_LOG
		exit $?
	fi
else
	echo "NO rollback needed!" >> $STARTUP_LOG
fi

echo "Startup Script Done!" >> $STARTUP_LOG
