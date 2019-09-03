#!/usr/bin/env ksh
################################################################################
# KSH SCRIPT FOR DEUTSCHE BANK - IAMR Health Check AUTOMATION                  #
# v3.0                                                                         #
# DEVELOPED BY DXC CLOUD AUTOMATION TEAM                                       #
# IN CASE OF QUERIES REACH OUT TO "DXC-DB Cloud DevOps and Run Team            #
#   <global-oc-db.cloud@dxc.com>"                                              #
#                               											   #
# PURPOSE OF THE SCRIPT : This script will do the Health Checks on IAMR SSH    #
#                         servers and generate the status report in HTML       #
#                         format for consolidating in single report.           #
#                               											   #
# FILE NAME             : health_checks.ksh                                    #
#------------------------------------------------------------------------------#
# VERSION HISTORY:                                                             #
# 1.0 INITIAL VERSION                                                          #
#------------------------------------------------------------------------------#
# 2.0 Version																   #
# Changes:-																	   #
#	1.	SCP logic added to do the DTG of Health Check outputs			       #
#------------------------------------------------------------------------------#
# 3.0 Version																   #
# Changes:-																	   #
#	1.	SCP user modifications											       #
#	2.	HTML mouse over message modifications								   #
################################################################################

################################################################################
#               DECLARE ALL THE VARIABLES IN THIS BLOCK                        #
################################################################################

# -----------------------------------------------------------------------------#
# Base Location & location for the run and conf logs                           #
# -----------------------------------------------------------------------------#
BASE_LOCATION="/home/svc-dtgautomation/health_check"

LOGS_BASE_LOCATION="/home/svc-dtgautomation/health_check"
LOGS_LOCATION="$LOGS_BASE_LOCATION/logs"
OUTPUTS_LOCATION="$LOGS_BASE_LOCATION/outputs"

# -----------------------------------------------------------------------------#
# Location of the script health_checks.ksh stored in Server                    #
# -----------------------------------------------------------------------------#
CURRENT_SCRIPT_LOCATION="$BASE_LOCATION/health_checks.ksh"
CURRENT_SCRIPT_CHECKSUM_LOCATION="$BASE_LOCATION/health_checks.checksum"

# -----------------------------------------------------------------------------#
# LOCKFILES for avoiding  Pre and Post Check conflicts and concurrent execution#
# -----------------------------------------------------------------------------#
PIDFILE_LOCATION="$LOGS_LOCATION/pid_lockfile"

# -----------------------------------------------------------------------------#
# Number of logs and outputs file instances needs to be retained			   #
# -----------------------------------------------------------------------------#
LOG_RETENTION_INSTANCE=5

# -----------------------------------------------------------------------------#
# All commands used in this script for finding the location                    #
# -----------------------------------------------------------------------------#
ALL_COMMANDS="echo date uname sed awk grep which rm xargs sort cat md5sum find wc mkdir basename cp scp ps tr tee head df iostat vmtoolsd uptime top free df ethtool netstat dmesg"

# -----------------------------------------------------------------------------#
# Thershold values for minor critical and Normal                   			   #
# -----------------------------------------------------------------------------#
MINOR_THRESHOLD=80
CRITICAL_THRESHOLD=90

# -----------------------------------------------------------------------------#
# Regional DTG server's hostnames and location	                   			   #
# -----------------------------------------------------------------------------#
UK_DTG_SERVER="ukwfvdtg001.mgt.dbn.hpe.com"
UK_DTG_LOCATION="/tmp"

US_DTG_SERVER="uspyvdtg001.mgt.dbn.hpe.com"
US_DTG_LOCATION="/data/dbuspy2dbwf"

DE_DTG_SERVER="degrvdtg001.mgt.dbn.hpe.com"
DE_DTG_LOCATION="/data/dbgr2dbwf"

SG_DTG_SERVER="sgkdvdtg001.mgt.dbn.hpe.com"
SG_DTG_LOCATION="/data/dbsg2dbwf"

################################################################################
#                       END OF VARIABLES DECLARATION                           #
################################################################################

################################################################################
#              DECLARE ALL THE FUNCTIONS IN THIS BLOCK                         #
################################################################################

# -----------------------------------------------------------------------------#
# Check the given returnCode and if it is not matches "0" Print and Log the    #
# given error message and exit with given error code.                          #
# -----------------------------------------------------------------------------#
errorExit()
{
    if [ $1 != 0 ]; then
        echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - ::HEALTH_CHECKS:: - [returnCode-$3] - $2"
        echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - ::HEALTH_CHECKS:: - [returnCode-$3] - $2" >> $LOGS_LOCATION/$script_runlog
        if [ ! -z $3 ]; then
            deletePIDFile
            exit $3
        fi
    fi
}

# -----------------------------------------------------------------------------#
# Check the given returnCode and if it is not matches "0" Print and Log the    #
# given error message in the runLog. If $3 value present execution of function #
# will be stopped.                                                             #
# -----------------------------------------------------------------------------#
errorLogPrint()
{
    if [ $1 != 0 ]; then
        echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - ::HEALTH_CHECKS:: - $2"
        echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - ::HEALTH_CHECKS:: - $2" >> $LOGS_LOCATION/$script_runlog
    fi
}

# -----------------------------------------------------------------------------#
# Log the given message string in the run log file only.                       #
# -----------------------------------------------------------------------------#
runLog()
{
    echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [INFO] - $@" >> $LOGS_LOCATION/$script_runlog
}

# -----------------------------------------------------------------------------#
# Log the given message string in the run log file only. if $2 is 1,           #
# it will print the content in the console or just log the information         #
# -----------------------------------------------------------------------------#
runLogPrint()
{
    echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [INFO] - $@" >> $LOGS_LOCATION/$script_runlog
    echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [INFO] - $@"
}

# -----------------------------------------------------------------------------#
# This function creates a PIDFILE with the script's running process ID         #
# -----------------------------------------------------------------------------#
createPIDFile()
{
    echo $$ > $PIDFILE_LOCATION
}

# -----------------------------------------------------------------------------#
# Remove the PIDFILE once script execution completed                           #
# -----------------------------------------------------------------------------#
deletePIDFile()
{
	runLog "Deleting PID LOCK file $PIDFILE_LOCATION"
	runLog "Executing Command \" rm -f $PIDFILE_LOCATION 2> /dev/null \" "
	rm -f $PIDFILE_LOCATION 2> /dev/null
	errorExit $? "Unable to delete PIDFILE" 114
}

# -----------------------------------------------------------------------------#
# Write HTML columns based on the color codes given					           #
# -----------------------------------------------------------------------------#
htmlColumn()
{
    echo "<td bgcolor=\"$1\" title=\"$3\"> $2 </td>" >> $OUTPUTS_LOCATION/$script_output
}

# -----------------------------------------------------------------------------#
# Write HTML Error Column											           #
# -----------------------------------------------------------------------------#
htmlColumnErrors()
{
    echo "$@" >> $OUTPUTS_LOCATION/$script_output_errors
}


# -----------------------------------------------------------------------------#
# Decide the status value by comparing the input value with threshold values   #
# -----------------------------------------------------------------------------#
decideStatus()
{
	input_value=$1
	input_module=$2
	if [ $input_value -lt $MINOR_THRESHOLD ]; then # Ex: less than 70
		htmlColumn "green" "<b>Normal</b>" "$input_module"
	elif [ $input_value -gt $MINOR_THRESHOLD ] && [ $input_value -lt $CRITICAL_THRESHOLD ]; then # Ex: Between 70 to 80
		htmlColumn "orange" "<b>Minor</b>" "$input_module"
	elif [ $input_value -gt $CRITICAL_THRESHOLD ]; then # Ex: more than 80
		htmlColumn "red" "<b>Critical</b>" "$input_module"
	else
		htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "$input_module"
	fi
}

# -----------------------------------------------------------------------------#
# Logs the given output in the summary log file only.                          #
# -----------------------------------------------------------------------------#
summaryLog()
{
	if [ -z $@ ]; then
		echo " Undefined / Failed " >> $LOGS_LOCATION/$script_summary
	else
		echo "$@" >> $LOGS_LOCATION/$script_summary
	fi
}

# -----------------------------------------------------------------------------#
# SCP the output file to the remote DTG server 						           #
# -----------------------------------------------------------------------------#
doDTG()
{
	runLogPrint "Copying outputs to the DTG server - $remote_dtg_server:/$remote_dtg_location..."
	runLog "Executing Command \" scp -p -q -o LogLevel=Quiet -o BatchMode=yes -o StrictHostKeYChecking=no $OUTPUTS_LOCATION/iamr_hc_output svc-dtgautomation@$remote_dtg_server:$remote_dtg_location 2> /dev/null \" "
	scp -p -q -o LogLevel=Quiet -o BatchMode=yes -o StrictHostKeYChecking=no $OUTPUTS_LOCATION/iamr_hc_output svc-dtgautomation@$remote_dtg_server:$remote_dtg_location 2> /dev/null
	scp_returnCode=$?
	errorExit $scp_returnCode "Failed to copy the reports using DTG" 117
	if [ $scp_returnCode -ne 0 ]; then
		errorLogPrint " $remote_dtg_server - SCP Failed(while transferring outputs) to server : $remote_dtg_server"
	fi
}

################################################################################
#                       END OF FUNCTIONS DECLARATION                           #
################################################################################

################################################################################
#               DECLARE ALL THE OPERATIONS IN THIS BLOCK                       #
################################################################################

# -----------------------------------------------------------------------------#
# Take current time as script start time                                       #
# -----------------------------------------------------------------------------#
script_starttime=`date +%d-%B-%y_%H%M%S`
script_runlog="iamr_hc_run_log_$script_starttime"
script_summary="iamr_hc_summary_$script_starttime"
script_output="iamr_hc_output_`uname -n`_$script_starttime"
script_output_errors="iamr_hc_output_errors"

# -----------------------------------------------------------------------------#
# Check OS matches SunOS, if not exit the script.                              #
# -----------------------------------------------------------------------------#
check_os=`uname 2> /dev/null`
if [ "$check_os" != "Linux" ]; then
    echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - [returnCode-113] - OS not matching the given filter criteria"
    exit 113
fi

# -----------------------------------------------------------------------------#
# Check the Log Directory is exists for run log. If not create the directory   #
# -----------------------------------------------------------------------------#
if [ ! -d "$LOGS_LOCATION" ]; then
    mkdir -p $LOGS_LOCATION 2> /dev/null
    if [ $? != 0 ]; then
        echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - [returnCode-111] - Failed to create conf log directory $RUN_LOG_LOCATION"
        exit 111
        deletePIDFile
    fi
fi

# -----------------------------------------------------------------------------#
# For checking the binary location for all commands in this script.            #
# -----------------------------------------------------------------------------#
for command in $ALL_COMMANDS; do
    binary_location=`which $command 2> /dev/null | grep '^[^no]'`
    binary_location_status=`echo "$binary_location" | sed '/^$/d' | wc -l`
    if [ $binary_location_status -eq 0 ]; then
		errorLogPrint 1 "Command \"$command\" not available in this system."
    else
        binary_location_out1=`echo "$binary_location" | grep -iv 'alias' | awk '{print $1}'`
        binary_location_out=`dirname "$binary_location"`
        export PATH=$PATH:$binary_location_out
    fi
done

# -----------------------------------------------------------------------------#
# Checksum file validatioN. Read and Delete the Checksum file. Check the       #
# checksum value for the script file and compare it with the value in checksum #
# file if its is not matching exit the script.                                 #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" cat $CURRENT_SCRIPT_CHECKSUM_LOCATION 2> /dev/null \" "
checksum=`cat $CURRENT_SCRIPT_CHECKSUM_LOCATION 2> /dev/null`
errorExit $? "Validating MD5 checksum failed" 101

runLog "Executing Command \" md5sum $CURRENT_SCRIPT_LOCATION 2> /dev/null \" "
compare_checksum=`md5sum $CURRENT_SCRIPT_LOCATION 2> /dev/null`
errorExit $? "Failed to run digest command for checksum validation" 103
compare_checksum=`echo "$compare_checksum" | awk '{print $1}'`
if [ ! "$checksum" == "$compare_checksum" ]; then
    errorExit 1 "Script file modified/corrupted (or) Validating MD5 checksum failed" 104
else
  	compare_checksum=`echo "$compare_checksum" | awk '{print $1}'`
fi

# -----------------------------------------------------------------------------#
# Check the Log Directory is exists for conf log. If not create the directory  #
# -----------------------------------------------------------------------------#
if [ ! -d "$OUTPUTS_LOCATION" ]; then
	runLog "Executing Command \" mkdir -p $OUTPUTS_LOCATION 2> /dev/null \" "
    mkdir -p $OUTPUTS_LOCATION 2> /dev/null
    if [ $? != 0 ]; then
        errorExit 1 "Failed to create conf log directory $OUTPUTS_LOCATION" 105
        deletePIDFile
    fi
fi

# -----------------------------------------------------------------------------#
# Prevents multiple instances of this script from running concurrently         #
# by using a lockfile containing the process ID.                               #
# -----------------------------------------------------------------------------#
if [ -f $PIDFILE_LOCATION ]; then
    runLog "Executing Command \" cat $PIDFILE_LOCATION 2> /dev/null \""
    pid=`cat $PIDFILE_LOCATION 2> /dev/null`
    errorExit $? "Failed to read PIDFILE" 106
    runLog "Executing Command \" ps 2> /dev/null \""
    pid_output=`ps 2> /dev/null`
    errorExit $? "Failed to execute ps command" 107
    runLog "Executing Command \" ps -o pid= -p $pid 2> /dev/null \""
    pid_status=`ps -o pid= -p $pid 2> /dev/null`
    if [ $pid -eq $pid_status ] && [ ! -z $pid ]; then
	    echo "`date \"+%d-%B-%y %H:%M:%S\"` - `uname -n` - [ERROR] - [returnCode-108] - Existing instance of this script already running"
        exit 108
    else
        createPIDFile 2> /dev/null
        errorExit $? "Unable to create PIDFILE" 109
    fi
else
    createPIDFile 2> /dev/null
    errorExit $? "Unable to create PIDFILE" 109
fi


# -----------------------------------------------------------------------------#
# Print the current date as Script Start time                                  #
# -----------------------------------------------------------------------------#
runLogPrint "################################################################################"
runLogPrint "Script start time : $script_starttime"
echo ""
runLogPrint "Health Checks - Running..."

# -----------------------------------------------------------------------------#
# Format First Column and last column header						           #
# -----------------------------------------------------------------------------#
htmlColumnErrors "<u><b>  Report Executed Time   </b></u><br> $script_starttime <br>"

local_hostname=`uname -n 2> /dev/null`

echo "<tr align=\"center\">" >> $OUTPUTS_LOCATION/$script_output
htmlColumn "blue" "<b>$local_hostname</b>" "$local_hostname"
summaryLog "Hostname : $local_hostname"

# -----------------------------------------------------------------------------#
# OS Version Checks															   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" cat /etc/redhat-release 2> /dev/null \""
os_version_cnt=`cat /etc/redhat-release 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$os_version\" | grep \"VERSION_ID\" | awk -F'\"' '{print \$2}' \""
	os_version=`echo "$os_version_cnt" | awk -F'[( ]' '{print $7}'`
	htmlColumn "green" "<b>$os_version</b>" "$os_version"
else
  	errorLogPrint 1 "Failed to run command \"cat /etc/os-release 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "OS Version Checks"
	htmlColumnErrors "<u><b>  OS Version Checks   </b></u><br>   Failed to run command \"cat /etc/os-release 2> /dev/null\"   <br>"
fi
summaryLog "OS Version : "
summaryLog "$os_version"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Kernel Version Checks														   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" uname -r 2> /dev/null \""
kernel_release=`uname -r 2> /dev/null`
if [ $? -eq 0 ]; then
	htmlColumn "green" "<b>$kernel_release</b>" "$kernel_release"
else
  	errorLogPrint 1 "Failed to run command \"uname -r 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Kernel Version Checks"
	htmlColumnErrors "<u><b>  Kernal Release Checks   </b></u><br>   Failed to run command \"uname -r 2> /dev/null\"   <br>"
fi
summaryLog "Kernel Release : "
summaryLog "$kernel_release"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# VM Tools Checks															   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" vmtoolsd -v 2> /dev/null \""
vmtools_check=`vmtoolsd -v 2> /dev/null`
if [ $? -eq 0 ]; then
 	htmlColumn "green" "<b>Normal</b>" "$vmtools_check"
else
  	errorLogPrint 1 "Failed to run command \" vmtoolsd -v 2> /dev/null \""
	htmlColumn "red" "<b>Critical</b>" "VM Tools Checks"
	htmlColumnErrors "<u><b>  VM Tools Checks   </b></u><br>   Failed to run command \" vmtoolsd -v 2> /dev/null \"   <br>"
fi
summaryLog "VM Tools Status : "
summaryLog "$vmtools_check"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# HP OVO Checks																   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" dzdo /opt/OV/bin/ovc -status 2> /dev/null \""
hpovo_check=`dzdo /opt/OV/bin/ovc -status 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$hpovo_check\" | grep -v \"Running\" | wc -l \""
	hpovo_check_rc=`echo "$hpovo_check" | grep -v "Running" | wc -l`
	if [ $hpovo_check_rc -eq 0 ]; then
 		htmlColumn "green" "<b>Normal</b>" "HP OVO Checks"
	else
		htmlColumn "red" "<b>Critical</b>" "HP OVO Checks"
	fi
else
  	errorLogPrint 1 "Failed to run command \" dzdo /opt/OV/bin/ovc -status 2> /dev/null \""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "HP OVO Checks"
	htmlColumnErrors "<u><b>  HP OVO Checks   </b></u><br>   Failed to run command \" dzdo /opt/OV/bin/ovc -status 2> /dev/null \"   <br>"
fi
summaryLog "HPOVO Status : "
summaryLog "$hpovo_check"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Server Load Average Checks												   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" uptime 2> /dev/null \""
server_load=`uptime 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$server_load\" | sed -n -e 's/^.*average: //p' | awk -F'.' '{print \$1}' \""
	server_load=`echo "$server_load" | sed -n -e 's/^.*average: //p' | awk -F'.' '{print $1}'`
	server_load=`printf "%0.0f\n" $server_load`
	
	if [ $server_load -lt 10 ]; then # Ex: less than 10
		htmlColumn "green" "<b>Normal</b>" "$server_load"
	elif [ $server_load -gt 10 ] && [ $server_load -lt 20 ]; then # Ex: Between 10 to 20
		htmlColumn "orange" "<b>Minor</b>" "$server_load"
	elif [ $server_load -gt 20 ]; then # Ex: more than 20
		htmlColumn "red" "<b>Critical</b>" "$server_load"
	else
		htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "$server_load"
	fi
else
  	errorLogPrint 1 "Failed to run command \" uptime 2> /dev/null \""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Server Load Average Checks"
	htmlColumnErrors "<u><b>  Server Load Average Checks   </b></u><br>   Failed to run command \" uptime 2> /dev/null \"   <br>"
fi
summaryLog "Server Load Average : "
summaryLog "$server_load"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# CPU Utilisation Checks													   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" top -b -n 1 2> /dev/null \""
top_out=`top -b -n 1 2> /dev/null`
top_rc=$?

if [ $top_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$top_out\" | grep \"Cpu(s)\" | awk -F'id' '{print \$1}' | awk -F'ni' '{print \$2}' | awk -F'[,.]' '{print \$2}'"
	cpu_idle=`echo "$top_out" | grep "Cpu(s)" | awk -F'id' '{print $1}' | awk -F'ni' '{print $2}' | awk -F'[,.]' '{print $2}'`
 	runLog "Executing Command \" printf \"%0.0f\n\" $cpu_idle \""
	cpu_idle=`printf "%0.0f\n" $cpu_idle`
	cpu_usage=100
	let cpu_usage-=cpu_idle
	
	decideStatus "$cpu_usage" "$cpu_usage"
else
  	errorLogPrint 1 "Failed to run command \"top -b -n 1 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "CPU Utilization Checks"
	htmlColumnErrors "<u><b>  CPU Utilization Checks   </b></u><br>   Failed to run command \"top -b -n 1 2> /dev/null\"   <br>"
fi
summaryLog "CPU Utilization : "
summaryLog "$cpu_usage"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Memory Utilisation Checks													   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" free -m 2> /dev/null \""
memory_output=`free -m 2> /dev/null`
memory_rc=$?

if [ $memory_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$memory_output\" | grep \"Mem:\" \""
	ram_usage=`echo "$memory_output" | grep "Mem:"`
	runLog "Executing Command \" echo \"$ram_usage\" | awk '{print \$2}' \""
	ram_total=`echo "$ram_usage" | awk '{print $2}'`
	runLog "Executing Command \" echo \"$ram_usage\" | awk '{print \$3}' \""
	ram_free=`echo "$ram_usage" | awk '{print $3}'`
	runLog "Executing Command \" awk \"BEGIN { pc=100*${ram_free}/${ram_total}; i=int(pc); print (pc-i<0.5)?i:i+1 }\" \""
	ram_calc=$(awk "BEGIN { pc=100*${ram_free}/${ram_total}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
	
	ram_calc=`printf "%0.0f\n" $ram_calc`
	decideStatus "$ram_calc" "$ram_calc"
else
  	errorLogPrint 1 "Failed to run command \"free -m 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Memory Utilization Checks"
	htmlColumnErrors "<u><b>  Memory Utilization Checks   </b></u><br>   Failed to run command \"free -m 2> /dev/null\"   <br>"
fi
summaryLog "Memory Utilization : "
summaryLog "$ram_calc"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# SWAP Utilisation Checks										   			   #
# -----------------------------------------------------------------------------#
if [ $memory_rc -eq 0 ]; then
	runLog "Executing Command \" echo "$memory_output" | grep "Swap:" \""
	swap_usage=`echo "$memory_output" | grep "Swap:"`
	runLog "Executing Command \" echo "$ram_usage" | awk '{print $2}' \""
	swap_total=`echo "$swap_usage" | awk '{print $2}'`
	runLog "Executing Command \" echo "$ram_usage" | awk '{print $3}' \""
	swap_free=`echo "$swap_usage" | awk '{print $3}'`
	runLog "Executing Command \" awk \"BEGIN { pc=100*${swap_free}/${swap_total}; i=int(pc); print (pc-i<0.5)?i:i+1 }\" \""
	swap_calc=$(awk "BEGIN { pc=100*${swap_free}/${swap_total}; i=int(pc); print (pc-i<0.5)?i:i+1 }")

	swap_calc=`printf "%0.0f\n" $swap_calc`
	decideStatus "$swap_calc" "$swap_calc"
else
  	errorLogPrint 1 "Failed to run command \"free -m 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "SWAP Utilization Checks"
	htmlColumnErrors "<u><b>  Disk Utilization Checks   </b></u><br>   Failed to run command \"free -m 2> /dev/null\"   <br>"
fi
summaryLog "SWAP Utilization : "
summaryLog "$swap_calc"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Disk IO Utilisation Checks												   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" iostat -xtc 2> /dev/null \""
disk_io_usage=`iostat -xtc 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$disk_io_usage\" | sed -n -e '/Device:/,\$p' | grep -v \"fd0\" | sed -n '1!p' | grep . | awk '{print \$14}' \""
 	disk_io_usage=`echo "$disk_io_usage" | sed -n -e '/Device:/,$p' | grep -v "fd0" | sed -n '1!p' | grep . | awk '{print $14}'`
	for io_line in $disk_io_usage; do 
		if [[ $io_line -gt $max_io_usge ]]; then
			max_io_usage=$io_line
		fi
	done
	
	max_io_usage=`printf "%0.0f\n" $max_io_usage`
	decideStatus "$max_io_usage" "Disk IO Utilization"
else
  	errorLogPrint 1 "Failed to run command \" iostat -xtc 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Disk IO Utilization Checks"
	htmlColumnErrors "<u><b>  SWAP Utilization Checks   </b></u><br>   Failed to run command \" iostat -xtc 2> /dev/null\"   <br>"
fi
summaryLog "Disk's max Utilization : "
summaryLog "$max_io_usage"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# File System Utilisation Checks											   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" df -h 2> /dev/null \""
fs_usage=`df -h 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"fs_usage\" | sed -n '1!p' | awk -F '%' '{print \$1}' | awk '{print \$5}' \""
	fs_usage=`echo "$fs_usage" | sed -n '1!p' | awk -F '%' '{print $1}' | awk '{print $5}'`
	for line in $fs_usage; do
		if [[ $line -gt $max_usge ]]; then
			max_usage=$line;
		fi;
	done
	
	max_usage=`printf "%0.0f\n" $max_usage`
	decideStatus "$max_usage" "$max_usage"
else
  	errorLogPrint 1 "Failed to run command \" df -h 2> /dev/null\""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "File System Utilization Checks"
	htmlColumnErrors "<u><b>  File System Utilization Checks   </b></u><br>   Failed to run command \" df -h 2> /dev/null\"   <br>"
fi
summaryLog "File System's max Utilization : "
summaryLog "$max_usage"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Network Link Status & Speed Checks										   #
# -----------------------------------------------------------------------------#

# -----------------------------------------------------------------------------#
# For Ethernet - 0															   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" dzdo ethtool eth0 2> /dev/null \""
eth0_output=`dzdo ethtool eth0 2> /dev/null`
eth0_rc=$?
if [ $eth0_rc -ne 0 ]; then
  	errorLogPrint 1 "Failed to run command \" dzdo ethtool eth0 2> /dev/null \""
	htmlColumnErrors "<u><b>  Network Status and Speed Checks   </b></u><br>   Failed to run command \" dzdo ethtool eth0 2> /dev/null \"   <br>"
else
	runLog "Executing Command \" echo \"$eth0_output\" | grep \"Link detected\" | awk -F':' '{print \$2}' \""
	eth0_link_status=`echo "$eth0_output" | grep "Link detected" | awk -F':' '{print $2}'`
	runLog "Executing Command \" echo \"$eth0_output\" | grep \"Speed\" | awk -F':' '{print \$2}' \""
	eth0_speed=`echo "$eth0_output" | grep "Speed" | awk -F':' '{print $2}'`
fi

# -----------------------------------------------------------------------------#
# For Ethernet - 1															   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" dzdo ethtool eth1 2> /dev/null \""
eth1_output=`dzdo ethtool eth1 2> /dev/null`
eth1_rc=$?
if [ $eth1_rc -ne 0 ]; then
  	errorLogPrint 1 "Failed to run command \" ethtool eth1 2> /dev/null \""
	htmlColumnErrors "<u><b>  Network Status and Speed Checks   </b></u><br>   Failed to run command \" ethtool eth1 2> /dev/null \"   <br>"
else
	runLog "Executing Command \" echo \"$eth1_output\" | grep \"Link detected\" | awk -F':' '{print \$2}' \""
	eth1_link_status=`echo "$eth1_output" | grep "Link detected" | awk -F':' '{print $2}'`
	runLog "Executing Command \" echo \"$eth1_output\" | grep \"Speed\" | awk -F':' '{print \$2}' \""
	eth1_speed=`echo "$eth1_output" | grep "Speed" | awk -F':' '{print $2}'`
fi

if [ $eth0_link_status == "yes" ] && [ $eth0_speed == "10000Mb/s" ] && [ $eth1_link_status == "yes" ] && [ $eth1_speed == "10000Mb/s" ]; then
	htmlColumn "green" "<b>Normal</b>" "Network Link Status & Speed Checks"
elif [ $eth0_rc -eq 0 ] || [ $eth1_rc -eq 0 ]; then
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Network Link Status & Speed Checks"
else
	htmlColumn "red" "<b>Critical</b>" "Network Link Status & Speed Checks"
fi

summaryLog "eth0 Link Status : "
summaryLog "$eth0_link_status"
summaryLog "eth0 Link Speed : "
summaryLog "$eth0_speed"
summaryLog "eth1 Link Status : "
summaryLog "$eth1_link_status"
summaryLog "eth1 Link Speed : "
summaryLog "$eth1_speed"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Network Routing Table Checks												   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" cat /etc/sysconfig/network 2> /dev/null \""
eth0_route=`cat /etc/sysconfig/network 2> /dev/null`
eth0_nr_rc=$?
if [ $eth0_nr_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$eth0_route\" | grep \"GATEWAY\" | awk -F'=' '{print \$2}' \""
 	eth0_route=`echo "$eth0_route" | grep "GATEWAY" | awk -F'=' '{print $2}'`
else
  	errorLogPrint 1 "Failed to run command \" cat /etc/sysconfig/network /dev/null \""
	htmlColumnErrors "<u><b>  Network Route Checks   </b></u><br>   Failed to run command \" cat /etc/sysconfig/network /dev/null \"   <br>"
fi

runLog "Executing Command \" cat /etc/sysconfig/network-scripts/route-eth1 2> /dev/null \""
eth1_route=`cat /etc/sysconfig/network-scripts/route-eth1 2> /dev/null`
eth1_nr_rc=$?
if [ $eth1_nr_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$eth1_route\" | awk '{print \$3}' \""
 	eth1_route=`echo "$eth1_route" | awk '{print $3}'`
else
  	errorLogPrint 1 "Failed to run command \" cat /etc/sysconfig/network-scripts/route-eth1 /dev/null \""
	htmlColumnErrors "<u><b>  Network Route Checks   </b></u><br>   Failed to run command \" cat /etc/sysconfig/network-scripts/route-eth1 /dev/null \"   <br>"
fi

runLog "Executing Command \" netstat -nr 2> /dev/null \""
netstat_output=`netstat -nr 2> /dev/null`
netstat_rc=$?
if [ $netstat_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$netstat_output\" | grep \"$eth0_route\" | wc -l \""
	eth0_nr_status=`echo "$netstat_output" | grep "$eth0_route" | wc -l`
	runLog "Executing Command \" echo \"$netstat_output\" | grep \"$eth1_route\" | wc -l \""
	eth1_nr_status=`echo "$netstat_output" | grep "$eth1_route" | wc -l`
else
	errorLogPrint 1 "Failed to run command \" netstat -nr /dev/null \""
	htmlColumnErrors "<u><b>  Network Route Checks   </b></u><br>   Failed to run command \" netstat -nr /dev/null \"   <br>"
fi

if [ $eth0_nr_rc -ne 0 ] || [ $eth1_nr_rc -ne 0 ] || [ $netstat_rc -ne 0 ]; then
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Network Routing Table Checks"
elif [ $eth0_nr_status -gt 0 ] && [ $eth1_nr_status -gt 0 ]; then
	htmlColumn "green" "<b>Normal</b>" "Network Routing Table Checks"
else
	htmlColumn "red" "<b>Critical</b>" "Network Routing Table Checks"
fi

summaryLog "eth0  - Routing Information: "
summaryLog "$eth0_route"
summaryLog "eth1  - Routing Information: "
summaryLog "$eth1_route"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Network Port Checks														   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" netstat -nlp 2> /dev/null \""
nw_ports=`netstat -nlp 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$nw_ports\" | grep -i 383 | wc -l \""
	nw_ports_out=`echo "$nw_ports" | grep -i 383`
	nw_ports_status1=`echo "$nw_ports_out" | grep "LISTEN" | wc -l`
	nw_ports_status2=`echo "$nw_ports_out" | grep "ESTABLISH" | wc -l`
	if [ $nw_ports_status1 -gt 0 ] || [ $nw_ports_status2 -gt 0 ]; then
		htmlColumn "green" "<b>Normal</b>" "Network Port Checks"
	else
		htmlColumn "red" "<b>Critical</b>" "Network Port Checks"
	fi
else
  	errorLogPrint 1 "Failed to run command \" netstat -nlp 2> /dev/null \""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Network Port Checks"
	htmlColumnErrors "<u><b>  Network Ports Checks  </b></u><br>   Failed to run command \" netstat -nlp 2> /dev/null \"   <br>"
fi
summaryLog "Network Port Status: "
summaryLog "$nw_ports"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# HPSA Client Agent Status Checks											   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" dzdo /opt/OV/bin/opcagt -status 2> /dev/null \""
hpsa_checks=`dzdo /opt/OV/bin/opcagt -status 2> /dev/null`
if [ $? -eq 0 ]; then
	runLog "Executing Command \" echo \"$hpsa_checks\" | grep -v \"Running\" | wc -l \""
 	hpsa_check_status=`echo "$hpsa_checks" | grep -v "Running" | wc -l`
	if [ $hpsa_check_status -gt 0 ]; then
		htmlColumn "red" "<b>Critical</b>" "HPSA Client Agent Status Checks"
	else
		htmlColumn "green" "<b>Normal</b>" "HPSA Client Agent Status Checks"
	fi
else
  	errorLogPrint 1 "Failed to run command \" dzdo /opt/OV/bin/opcagt -status 2> /dev/null \""
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "HPSA Client Agent Status Checks"
	htmlColumnErrors "<u><b>  HPSA Checks   </b></u><br>   Failed to run command \" dzdo /opt/OV/bin/opcagt -status 2> /dev/null \"   <br>"
fi
summaryLog "HPSA Agent Status: "
summaryLog "$nw_ports_status"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Event Log Checks Checks													   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" dmesg 2> /dev/null \""
event_logs_cnt=`dmesg 2> /dev/null`
dmesg_rc=$?
if [ $dmesg_rc -eq 0 ]; then
	runLog "Executing Command \" echo \"$event_logs_cnt\" | grep -i error | wc -l \""
	event_logs=`echo "$event_logs_cnt" | grep -i error`
	event_logs_status=`echo "$event_logs" | wc -l`
else
  	errorLogPrint 1 "Failed to run command \" dmesg 2> /dev/null \""
	htmlColumnErrors "<u><b>  Event Log Checks   </b></u><br>   Failed to run command \" dmesg 2> /dev/null \"   <br>"
fi

runLog "Executing Command \" dzdo cat /var/log/messages 2> /dev/null \""
log_messages_cnt=`dzdo cat /var/log/messages  2> /dev/null`
log_msg_rc=$?
if [ $log_msg_rc -eq 0 ]; then
	runLog "Executing Command \"  echo \"$log_messages_cnt\" | grep -i error | wc -l \""
	log_messages=`echo "$log_messages_cnt" | grep -i error`
	log_messages_status=`echo "$log_messages"  | wc -l`
else
  	errorLogPrint 1 "Failed to run command \" cat /var/log/messages 2> /dev/null \""
	htmlColumnErrors "<u><b>  Event Log Checks   </b></u><br>   Failed to run command \" cat /var/log/messages 2> /dev/null \"   <br>"
fi

if [ $dmesg_rc -ne 0 ] || [ $log_msg_rc -ne 0 ]; then
	htmlColumn "yellow" "<b>Unknown / Command Failed</b>" "Event Log Checks"
elif [ $event_logs_status -eq 0 ] && [ $log_messages_status -eq 0 ]; then
	htmlColumn "green" "<b>Normal</b>" "Event Log Checks"
else
	htmlColumn "red" "<b>Critical</b>" "Event Log Checks"
fi

summaryLog "No. Error Messages in dmesg command : "
summaryLog "$event_logs"
summaryLog "No. Error Messages in Logs messages : "
summaryLog "$log_messages"
summaryLog "________________________________________________________________________________"

# -----------------------------------------------------------------------------#
# Read the appended error log files content and write into last column         #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" cat $OUTPUTS_LOCATION/$script_output_errors 2> /dev/null \""
all_errors=`cat $OUTPUTS_LOCATION/$script_output_errors 2> /dev/null`
runLog "Executing Command \" cat $OUTPUTS_LOCATION/$script_output_errors 2> /dev/null \""
rm $OUTPUTS_LOCATION/$script_output_errors 2> /dev/null

htmlColumn "white" "$all_errors" "Error Messages"

# -----------------------------------------------------------------------------#
# Complete the HTML table row										           #
# -----------------------------------------------------------------------------#
echo "</tr>" >> $OUTPUTS_LOCATION/$script_output

# -----------------------------------------------------------------------------#
# Copy the content of the recently created output file to static output file   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" cp $OUTPUTS_LOCATION/$script_output $OUTPUTS_LOCATION/iamr_hc_output 2> /dev/null \""
cp $OUTPUTS_LOCATION/$script_output $OUTPUTS_LOCATION/iamr_hc_output 2> /dev/null
errorExit $? "Failed to copy the Health Check otuput to static output file" 112

# -----------------------------------------------------------------------------#
# Set permission for the output file reated   #
# -----------------------------------------------------------------------------#
runLog "Executing Command \" chmod 666 $OUTPUTS_LOCATION/iamr_hc_output 2> /dev/null \""
chmod 666 $OUTPUTS_LOCATION/iamr_hc_output 2> /dev/null
errorExit $? "Failed to set file permission for the output file" 118


# -----------------------------------------------------------------------------#
# Check the region based on the local host's name and decide which dtg server  #
# and location needs to be used.
# -----------------------------------------------------------------------------#
check_local_region=`echo "$local_hostname" | cut -c1-2 | tr '[:upper:]' '[:lower:]'`

check_local_hostname=`echo "$local_hostname" | awk -F'.' '{print $1}'`

if [ $check_local_region == "uk" ]; then
	remote_dtg_server=$UK_DTG_SERVER
	remote_dtg_location="$UK_DTG_LOCATION/iamr_unix_hc_$check_local_hostname"
	doDTG
	
elif [ $check_local_region == "us" ]; then
	remote_dtg_server=$US_DTG_SERVER
	remote_dtg_location="$US_DTG_LOCATION/iamr_unix_hc_$check_local_hostname"
	doDTG
	
elif [ $check_local_region == "de" ]; then
	remote_dtg_server=$DE_DTG_SERVER
	remote_dtg_location="$DE_DTG_LOCATION/iamr_unix_hc_$check_local_hostname"
	doDTG
	
elif [ $check_local_region == "sg" ]; then
	remote_dtg_server=$SG_DTG_SERVER
	remote_dtg_location="$SG_DTG_LOCATION/iamr_unix_hc_$check_local_hostname"
	doDTG
	
else
	errorLogPrint 1 "Unable to find local region for copying the reports using DTG."
fi

# -----------------------------------------------------------------------------#
# Remove the old run logs. Keep only last n-1 instance's logs                  #
# -----------------------------------------------------------------------------#
if [ -d "$LOGS_LOCATION" ]; then
	run_log_redention=$LOG_RETENTION_INSTANCE
	let run_log_redention*=2
	let run_log_redention+=1
	
    runLog "Finding the old run logs for deletion"
	runLog "Executing Command \" find $LOGS_LOCATION/iamr_hc_* -type f -printf \"\n%AD %AT %p\" | sort -r | tail -n +$run_log_redention 2> /dev/null \""
    OLD_FILES=`find $LOGS_LOCATION/iamr_hc_* -type f -printf "\n%AD %AT %p" | sort -r | tail -n +$run_log_redention 2> /dev/null`
	errorExit $? "Unable to find old run log files for removal" 116
	FILES_COUNT=`echo "$OLD_FILES" | wc -l`
    if [ "$FILES_COUNT" -gt 0 ]; then
        runLog "Below old run log files will be removed,"
        runLog "`find $LOGS_LOCATION/iamr_hc_* -type f -printf \"\n%AD %AT %p\" | sort -r | tail -n +$run_log_redention | awk '{print $3}'`"
        runLog "Deleting the old script run files"
		runLog "Executing Command \" find $LOGS_LOCATION/iamr_hc_* -type f -printf \"\n%AD %AT %p\" | sort -r | awk '{print \$3}' | tail -n +$run_log_redention | xargs rm -f 2> /dev/null \""
        find $LOGS_LOCATION/iamr_hc_* -type f -printf "\n%AD %AT %p" | sort -r | awk '{print $3}' | tail -n +$run_log_redention | xargs rm -f 2> /dev/null
        errorExit $? "Old run log files removal failed." 110
    else
        runLog "There is no old run log files found for deletion"
    fi
fi

# -----------------------------------------------------------------------------#
# Remove the outputs. Keep only last n-1 instance's logs                       #
# -----------------------------------------------------------------------------#
if [ -d "$OUTPUTS_LOCATION" ]; then
	output_log_redention=$LOG_RETENTION_INSTANCE
	let output_log_redention+=1
	
    runLog "Finding the old output logs for deletion"
	runLog "Executing Command \" find $OUTPUTS_LOCATION/iamr_hc_output_* | sort -r | tail -n +$output_log_redention 2> /dev/null \""
    OLD_FILES=`find $OUTPUTS_LOCATION/iamr_hc_output_* | sort -r | tail -n +$output_log_redention 2> /dev/null`
	errorExit $? "Unable to find old run log files for removal" 116
	FILES_COUNT=`echo "$OLD_FILES" | wc -l`
    if [ "$FILES_COUNT" -gt 0 ]; then
        runLog "Below old output files will be removed,"
        runLog "`find $OUTPUTS_LOCATION/iamr_hc_output_* | sort -r | tail -n +$output_log_redention`"
        runLog "Deleting the old output files"
		runLog "Executing Command \" find $OUTPUTS_LOCATION/iamr_hc_output_* | sort -r | tail -n +$output_log_redention | xargs rm -f 2> /dev/null \""
        find $OUTPUTS_LOCATION/iamr_hc_output_* | sort -r | tail -n +$output_log_redention | xargs rm -f 2> /dev/null
        errorExit $? "Old run log files removal failed." 110
    else
        runLog "There is no old run log files found for deletion"
    fi
fi

runLogPrint "Health Checks - Completed."

# -----------------------------------------------------------------------------#
# Triggers the function for deleting the PIDFile                               #
# -----------------------------------------------------------------------------#
deletePIDFile

runLogPrint "Script Start time : $script_starttime"
runLogPrint "Script End time : $script_starttime"
runLogPrint "################################################################################"

exit 0

################################################################################
#                       END OF OPERATIONS DECLARATION                          #
################################################################################

#E.O.F
