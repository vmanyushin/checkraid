#!/bin/bash

function test_hp_check_volume_status
{
	echo $(cat ../test/volume_${2} | grep -v "^$" | sed -re "s/\s+//" | awk -F": " '{print $2}')
}

function test_hp_check_disk_status
{
	echo $(cat ../test/$2 | grep -v "^$" | sed -re "s/\s+//" | awk -F": " '{print $2}')
}

function test_hp_get_drive_type
{
	local line DEVICE_TYPE

	for line in $(cat ../test/$2_full | grep -v "^$" | sed -re "s/\s{2,}//")	
	do
		[[ $line =~ "Drive Type:" ]] && DEVICE_TYPE="${line#Drive Type:[[:space:]]}"
	done

	echo $DEVICE_TYPE
}

function test_hp_get_drive_serial
{
	local line DEVICE_SERIAL

	for line in $(cat ../test/$2_full | grep -v "^$" | sed -re "s/\s{2,}//")	
	do
		[[ $line =~ "Serial Number:" ]] && DEVICE_SERIAL="${line#Serial Number:[[:space:]]}"
	done

	DEVICE_SERIAL=$(echo $DEVICE_SERIAL | sed -re "s/^\s*//; s/\s{2,}/ /")

	echo $DEVICE_SERIAL
}


function test_hp_get_volume_type
{
	echo $(cat ../test/volume_${2}_full | grep "Fault Tolerance:" | sed -re "s/^\s*//" | awk -F": " '{print $2}')
}