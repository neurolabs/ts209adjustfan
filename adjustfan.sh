#!/bin/bash

################################################################################
# adjustfan - Cron Script to control fan by hdd temperature for TS-209
#
#   Measures the temperature of disks. If it reaches a threshold, turns on the
#   fan. If it reaches a low threshold or if the disks are spun down, turns off
#   the fan.
#
#
# Version
#   0.2
#
# Usage
#   Edit the following variables:
#     DEVICES  - A bash array containing the disks of which the temperature
#                should be measured.
#     MAXTEMP  - The high threshold. If higher temperatures are measured, the
#                fan is turned on.
#     MINTEMP  - The low threshold. If lower temperatures are measured, or if
#                no temperature can be determined ( = spun down disks ), the
#                fan is turned off.
#     HDDTEMP  - The path to the hddtemp executable.
#     QCONTROL - The path to the qcontrol executable.
#     LOGGING  - If "1", writes a log to /var/log/adjustfan.log
#
#   If you want to keep your disks spun down as much as possible, turn off the
#   logging or mount /var/log on a separate device. And keep in mind that
#   reading the temperature from disk is a read operation, which prevents
#   spindown. So the interval at which this script is triggered must be larger
#   than the spindown timeout configured on the disks.
#   Logging of course is a write operation on the disk. I've worked around that
#   problem by mounting a usb stick on /var/log.
#   If you configure a high interval, please keep in mind that the disks get
#   hotter between intervals. So first measure how much hotter the disks get
#   during your preferred interval.
#   My disks approximately gain 5°C in 15 minutes under high load, and I don't
#   want them to get hotter than 40°C, so I configured this script to run every
#   15 minutes and set the MAXTEMP variable to 35°C.
#  
# Prerequisites
#   bash, qcontrol, hddtemp, sed
#
# TODO
#   * Find out if CPU Temperature can be read and considered as well
#
# CHANGELOG
#   0.2
#     * no dependance on running qcontrol - will use running instance or create
#       a qcontrol instance for a single run as necessary
#     * better hdd sleep handling, sleeping disks are recognized and treated
#       accordingly
#     * better failsafe, will turn on fan if in doubt
#   0.1
#     * initial simple version
################################################################################

# Configuration

DEVICES=( /dev/sda /dev/sdb )
MAXTEMP=35
MINTEMP=30
HDDTEMP=/usr/sbin/hddtemp
QCONTROL=/usr/sbin/qcontrol
LOGGING=1

# Implementation

function log {
  [[ "$LOGGING" == "1" ]] && echo `date +"%Y-%m-%d %T"` $* >> /var/log/adjustfan.log
}

function setfan {
  speed=$1
  $QCONTROL fanspeed $speed 2>&1 > /dev/null
  # if no qcontrol daemon is running, set it up just for this run
  if [[ "$?" == "255" ]]; then
    log setting up qcontrol daemon
    # clear socket if exists for this run
    [[ -e /var/run/qcontrol.sock ]] && rm /var/run/qcontrol.sock
    $QCONTROL -d &
    # the daemon needs some time before handling queries
    sleep 5
    $QCONTROL fanspeed $speed
    kill %1
    # clear socket if exists for future runs
    [[ -e /var/run/qcontrol.sock ]] && rm /var/run/qcontrol.sock
  fi
}

CURRTEMP=-10
for ((a=0; a < ${#DEVICES[*]} ; a++)); do
  OUTPUT=`$HDDTEMP ${DEVICES[${a}]} 2>&1`
  log $OUTPUT
  SLEEPING=`echo $OUTPUT|grep sleeping|wc -l`
  log $SLEEPING
  if [[ "$SLEEPING" == "1" ]]; then
    log drive ${DEVICES[${a}]} is sleeping
    TEMP=-2
  else
    TEMP=`echo $OUTPUT|sed 's/^.*:\s*\([0-9]*\).*$/\1/g'`
  fi
  
  # check if a valid temperature was extracted, and if yes, extract highest temp
  expr $TEMP + 1 2>&1 > /dev/null
  RETVAL=$?
  if [[ "$RETVAL" !=  "0" || ! -n "$TEMP" ]]; then
    log Could not extract a valid temperature from disk ${DEVICES[${a}]}. Extracted temperature: "$TEMP", return value "$RETVAL"
  else
    if [[ "$TEMP" -gt "$CURRTEMP" ]]; then
      CURRTEMP=$TEMP
    fi
  fi
done

# do we have any temperature from a device? If not, turn on fan
if [[ "$CURRTEMP" == "-10" ]]; then
  log no valid temperature extracted, check config. Turning on fan and exiting
  setfan full
  exit 1
fi

# is any drive sleeping?
if [[ "$CURRTEMP" == "-2" ]]; then
  log drives are sleeping, turning fan off
  setfan stop
  exit 1
fi

log current hdd temperature: $CURRTEMP

if [[ "$CURRTEMP" -ge "$MAXTEMP" ]]; then
  log max temp reached, turning on fan
  setfan full
else
  if [[ "$CURRTEMP" -lt "$MINTEMP" ]]; then
    log min temp reached or hdds spun down, turning off fan
    setfan stop 
  fi
fi
