#!/bin/sh

IOE_DIR=$1
START_TIME_FILE=/tmp/ioe_start_time.txt
STARTUP_LOG=/tmp/ioe_startup.log

cd $IOE_DIR

date > $START_TIME_FILE
date +%s >> $START_TIME_FILE

echo "Starting..." > $STARTUP_LOG
date +"Start Time: %c" >> $STARTUP_LOG
# Wait for strip_done
if [ -f $IOE_DIR/ipt/strip_mode ]
then
	i=1
	while [ $i -le 300 ]
	do
		if [ -f $IOE_DIR/ipt/strip_done ]
		then
			if [ $i -gt 1 ]
			then
				sync
			fi
			break
		fi
		sleep 1
		let i++
	done
fi
# User startup script
if [ -f $IOE_DIR/ipt/startup.sh ]
then
	sh $IOE_DIR/ipt/startup.sh >> $STARTUP_LOG
fi
# Do upgrade if required
if [ -f $IOE_DIR/ipt/upgrade ]
then
	echo "Upgrade script detected! Upgrading FreeIOE system!" >> $STARTUP_LOG
	sh $IOE_DIR/ipt/upgrade.sh >> $STARTUP_LOG
	rm -f $IOE_DIR/ipt/upgrade # delete upgrade flag file always
	if [ $? -ne 0 ]; then
		echo "Failed to run upgrade script" >> $STARTUP_LOG
		exit $?
	fi
else
	echo "No upgrade needed!" >> $STARTUP_LOG
fi
# Do rollback
if [ -f $IOE_DIR/ipt/rollback ]
then
	echo "Rollback script detected! Rolling back FreeIOE system!" >> $STARTUP_LOG
	sh $IOE_DIR/ipt/rollback.sh >> $STARTUP_LOG
	if [ $? -eq 0 ]; then
		rm -f $IOE_DIR/ipt/rollback
	else
		echo "Failed to run rollback script" >> $STARTUP_LOG
		exit $?
	fi
else
	echo "No rollback needed!" >> $STARTUP_LOG
fi

# skynet's config compat
if [ -f $IOE_DIR/skynet/ioe/config.path.compat ]; then
	echo "Found config.path.compat file..." >> $STARTUP_LOG
	. $IOE_DIR/skynet/ioe/scripts/functions.sh
	set -- $(read_version "${IOE_DIR}/skynet/version")
	sver=$1
	echo "Skynet Ver: $sver" >> $STARTUP_LOG
	if [ "$sver" -lt 2547 ]; then
		echo "Using config.path.compat instead of config.path" >> $STARTUP_LOG

		# Backup existing config.path if present
		if [ -f $IOE_DIR/skynet/ioe/config.path ]; then
			backup_file="$IOE_DIR/skynet/ioe/config.path.backup"
			echo "Backing up existing config.path to: $(basename "$backup_file")" >> $STARTUP_LOG
			mv $IOE_DIR/skynet/ioe/config.path "$backup_file"
			if [ $? -ne 0 ]; then
				echo "Failed to backup config.path" >> $STARTUP_LOG
			fi
		fi

		mv $IOE_DIR/skynet/ioe/config.path.compat $IOE_DIR/skynet/ioe/config.path
		if [ $? -ne 0 ]; then
			echo "Failed to move config.path.compat to config.path" >> $STARTUP_LOG
			exit 1
		fi
		echo "Successfully applied config.path.compat" >> $STARTUP_LOG
	fi
fi

if [ -f $IOE_DIR/.env ]
then
	set -o allexport; source $IOE_DIR/.env; set +o allexport
fi

sync &

echo "Startup script completed!" >> $STARTUP_LOG
