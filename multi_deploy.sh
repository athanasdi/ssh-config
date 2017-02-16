#!/bin/bash


# Creating the logs directory
[[ -d $mydir ]] || mkdir -p "logs"

# This script will run the deploy.sh on all hosts listed in hosts.txt file
awk '{print $1}' < hosts.txt | while read IP; do 
	echo "Configuring: $IP"
	LOG_FILE="logs/log_${IP}.log"

	# Configure machine with $IP and create the log file
	SERVER_IP=${IP} ./deploy.sh "$@" > $LOG_FILE 2>&1

	# Check for errors 
	[ $? -eq 0 ] && echo "OK" || echo "Configuring: $IP returned with an error. Check log files."
done