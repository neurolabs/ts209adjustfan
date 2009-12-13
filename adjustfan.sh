#!/bin/bash

################################################################################
# adjustfan - Cron Script to control fan by hdd temperature for TS-209
#
#   Measures the temperature of disks. If it reaches a threshold, turns on the
#   fan. If it reaches a low threshold or if the disks are spun down, turns off
#   the fan.
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
#
#   If you want to keep your disks spun down as much as possible, turn off the
#   logging or mount /var/log on a separate device. And keep in mind that
#   reading the temperature from disk is a read operation, which prevents
#   spindown. So the interval at which this script is triggered must be larger
#   than the spindown timeout configured on the disks.
#   If you configure a high interval, please keep in mind that the disks get
#   hotter between intervals. So first measure how much hotter the disks get
#   during your preferred interval.
#   My disks approximately gain 5°C in 15 minutes under high load, and I don't
#   want them to get hotter than 40°C, so I configured this script to run every
#   15 minutes and set the MAXTEMP variable to 35°C.
#  
# Prerequisites
#   bash, qcontrol, hddtemp, awk
#
# TODO
#   * Find out if CPU Temperature can be read and considered as well
#   * Make logging configurable
#   * replace awk calls by single sed call
################################################################################

# Configuration

DEVICES=( /dev/sda /dev/sdb )
MAXTEMP=35
MINTEMP=25
HDDTEMP=/usr/sbin/hddtemp
QCONTROL=/usr/sbin/qcontrol

# Implementation

function log {
  echo `date +"%Y-%m-%d %T"` $* >> /var/log/adjustfan.log
}

CURRTEMP=-1
for ((a=0; a < ${#DEVICES[*]} ; a++)); do
  FOO=`$HDDTEMP ${DEVICES[${a}]} 2>/dev/null|awk '{print $4}'|awk -F"°" '{print $1}'`
  if [[ "$FOO" -gt "$CURRTEMP" ]]; then
    CURRTEMP=$FOO
  fi
done

log current hdd temperature: $CURRTEMP

if [[ "$CURRTEMP" -ge "$MAXTEMP" ]]; then
  log max temp reached, turning on fan
  $QCONTROL fanspeed full
else
  if [[ "$CURRTEMP" -lt "$MINTEMP" ]]; then
    log min temp reached or hdds spun down, turning off fan
    $QCONTROL fanspeed stop 
  fi
fi
