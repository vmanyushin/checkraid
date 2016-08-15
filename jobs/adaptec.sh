#!/bin/bash

. ./checkraid_vars.sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

OLD_IFS=$IFS
IFS=$'\n'

for line in $(arcconf GETCONFIG 1 AD)
do
	[[ $line =~ "Controller Status" ]] && CONTROLLER_STATUS="${line#[[:space:]]*Controller Status[[:space:]]*:[[:space:]]}"
	[[ $line =~ "Logical devices/Failed/Degraded" ]] &&	CONTROLLER_DEVICES="${line#[[:space:]]*Logical devices/Failed/Degraded[[:space:]]*:[[:space:]]}"
done

VOLUME_TOTAL=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f1)
VOLUME_FAILED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f2)
VOLUME_DEGRADED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f3)

echo "Controller Status: ${CONTROLLER_STATUS}" > $VARDIR/adaptec/current_state

for volume in $(seq 0 $(expr $VOLUME_TOTAL - 1)); do
	for line in $(arcconf GETCONFIG 1 LD "$volume"); do
		[[ $line =~ "Logical Device name" ]] && VOLUME_DEVICE_NAME="${line#[[:space:]]*Logical Device name[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Status of Logical Device" ]] && VOLUME_STATUS="${line#[[:space:]]*Status of Logical Device[[:space:]]*:[[:space:]]}"
	done
	echo "Volume: ${VOLUME_DEVICE_NAME}, Status: ${VOLUME_STATUS}" >> $VARDIR/adaptec/current_state
done

IFS=$OLD_IFS

STATE1=$(md5sum $VARDIR/adaptec/initial_state | cut -d" " -f1 )
STATE2=$(md5sum $VARDIR/adaptec/current_state | cut -d" " -f1 )

if [[ "$STATE1" != "$STATE2" ]]; then
    logger -t adaptec-mon "состояние RAID контроллера или одного из массивов изменился"
else
    logger -t adaptec-mon "состояние RAID контроллера и массивов оптимальное"
fi