#!/bin/bash
#
# created: 04.08.2016
# updated: 
# author: vmanyushin@gmail.com
# version: 0.1
# description:
#

function software_raid_check
{
	if [[ $(which mdadm | grep mdadm -c ) -ne 1 ]]; then
		fail "в системе присутствуют RAID массивы но не установлен mdadm"
		echo ""
		return
	fi

	local RAID_DEVICES=$(grep ^md -c /proc/mdstat)
	[[ $DEBUG == true ]] && debug "total RAID devices = ${RAID_DEVICES}"

	if [[ $RAID_DEVICES == 0 ]]; then 
		return
	fi

	if [[ $RAID_DEVICES > 0 ]]; then
		echo "В системе обнаружен SOFTRAID"
		echo -n "Количество RAID массивов в системе = "
		ok "${RAID_DEVICES}" 
		echo ""
	fi

	local RAID_NAME RAID_LEVEL RAID_SIZE RAID_ACTIVE_DEVICES RAID_WORKING_DEVICES RAID_FAILED_DEVICES RAID_SPARE_DEVICES RAID_STATUS
	local array name meta name2 uuid line

	while read array name meta name2 uuid
	do
		[[ $DEBUG == true ]] && debug "${array} ${name} ${meta} ${name2} ${uuid}"

		if [[ $DEBUG == true ]]; then
			OLD_IFS=$IFS
			IFS=$'\n'

			for line in $(mdadm --detail $name)
			do
				debug $line
			done

			IFS=$OLD_IFS
		fi

    	RAID_NAME=$(mdadm --detail $name | head -n 1 | cut -d '/' -f 3,4 | tr -d '#\[/:\]#')
    	RAID_LEVEL=$(mdadm --detail $name | grep 'Raid Level' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_SIZE=$(( $(mdadm --detail $name | grep 'Array Size' | cut -d ':' -f 2 | cut -d ' ' -f 2 | tr -d '[[:space:]]') / 1024 ))
    	RAID_ACTIVE_DEVICES=$(mdadm --detail $name | grep 'Raid Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_WORKING_DEVICES=$(mdadm --detail $name | grep 'Working Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_FAILED_DEVICES=$(mdadm --detail $name | grep 'Failed Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_SPARE_DEVICES=$(mdadm --detail $name | grep 'Spare Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_STATUS=$(mdadm --detail $name | grep 'State :' | cut -d ':' -f 2 | tr -d '[[:space:]]')


    	echo ""
		rpad "Название устройства" 32 " : ${RAID_NAME}\n"
		rpad "Типа массива" 32 " : ${RAID_LEVEL}\n"
		rpad "Размер массива" 32 " : ${RAID_SIZE}Mb\n"
		rpad "Кол-во дисков" 32 " : ${RAID_ACTIVE_DEVICES}\n"
		rpad "Кол-во работающих дисков" 32 ": ${RAID_WORKING_DEVICES}\n" 
		rpad "Кол-во дисков гор. замены" 32 " : ${RAID_SPARE_DEVICES}\n"

		
		[[ $RAID_FAILED_DEVICES -gt 0 ]] && rpad "Кол-во сбойных дисков" 32 " : ${COLOR_RED}${RAID_FAILED_DEVICES}${COLOR_NORMAL}"; 
		[[ $RAID_FAILED_DEVICES -gt 0 ]] && rpad "Кол-во сбойных дисков" 32 " : ${COLOR_GREEN}${RAID_FAILED_DEVICES}${COLOR_NORMAL}"; 

		[[ $RAID_STATUS == "clean" ]] && rpad "Статус массива" 32 " : ${COLOR_GREEN}${RAID_STATUS}${COLOR_NORMAL}"; 
		[[ $RAID_STATUS != "clean" ]] && rpad "Статус массива" 32 " : ${COLOR_RED}${RAID_STATUS}${COLOR_NORMAL}"; 

		echo ""

		local FPOS LPOS

		FPOS=$(expr `mdadm --detail $name | grep -n RaidDevice | cut -d ':' -f 1` + 1)
		LPOS=$(mdadm --detail $name | wc -l)

		echo ""
		echo "Статус устройств массива"

		local filename="/tmp/${RANDOM}.random.txt"
		touch $filename

		echo -e "Устройство\tМодель\tСерийный номер\tСинхронизирован\tСтатус" > $filename

		local number major minor device state 

		while read number major minor device state 
		do
			status=(${state// / })
			
			local dev_state dev_sync dev_name

			dev_state=${status[0]}
			dev_sync=${status[1]}
			dev_name=${status[2]}

			if [[ $(grep 'VBOX' /sys/class/block/sde/device/vendor) ]]; then
				dev_model=virtualbox
				dev_serial=virtualbox
			else 
				dev_model=$(hdparm -i $dev_name | grep Model | sed -e 's/^\s//' | awk -F", " '{ split($1,m,"="); print m[2]}')
				dev_serial=$(hdparm -i $dev_name | grep Model | sed -e 's/^\s//' | awk -F", " '{ split($3,m,"="); print m[2]}')
			fi

			[[ $dev_state == "active" ]] && dev_state="\033[0;32m${dev_state}\e[0m"
			[[ $dev_state != "active" ]] && dev_state="\033[0;31m${dev_state}\e[0m"

			echo -e "${dev_name}\t${dev_model}\t${dev_serial}\t${dev_sync}\t${dev_state}" >> $filename
		done < <(mdadm --detail $name | sed -n ${FPOS},${LPOS}p)

		tput sgr0
		table_output $filename
		tput sgr0

	done < <(mdadm --detail --scan)

	echo "Убедитесь, что информация верна и отсутствуют ошибки"
	read -p  "сохранить данную конфигурацию Y/n"  -n 1 -r

	local REPLY

	if [[ $REPLY =~ ^[Nn]$ ]]; then
		return
	fi

	echo ""

	cat /proc/mdstat > $SOFTRAID_INIT_STATE

	if [[ ! -e $SOFTRAID_INIT_STATE ]]; then
		echo "произошла ошибка при сохранении данных"
		exit 1
	fi

	echo "данные сохранены, ставим массив на мониторинг"
	echo ""
	echo "*/$CRONTAB_REFRESH_TIME * * * * root cd $CWD && ./jobs/mdadm.sh" > /etc/cron.d/mdadm-monitor
}

function adaptec_raid_check
{
	if [[ $(which arcconf | grep arcconf -c ) -ne 1 ]]; then
		fail "в системе присутствуют RAID массивы но не установлен arcconf"
		echo ""
		
		read -p "Скачать и установить arcconf Y/n? " -n 1 -r
		if [[ $REPLY =~ ^[Nn]$ ]]; then
			exit 1	
		fi

		install_raid_utils "ARCCONF"
	fi

	OLD_IFS=$IFS
	IFS=$'\n'

	local line CONTROLLER_STATUS CONTROLLER_MODEL CONTROLLER_TEMPERATURE CONTROLLER_MEMORY CONTROLLER_PERFMODE CONTROLLER_DEVICES

	for line in $(arcconf GETCONFIG 1 AD)
	do
		[[ $DEBUG == true ]] &&  debug $line

		[[ $line =~ "Controller Status" ]] && CONTROLLER_STATUS="${line#[[:space:]]*Controller Status[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Controller Model" ]] && CONTROLLER_MODEL="${line#[[:space:]]*Controller Model[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Temperature" ]] &&	CONTROLLER_TEMPERATURE="${line#[[:space:]]*Temperature[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Installed memory" ]] && CONTROLLER_MEMORY="${line#[[:space:]]*Installed memory[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Performance Mode" ]] && CONTROLLER_PERFMODE="${line#[[:space:]]*Performance Mode[[:space:]]*:[[:space:]]}"
		[[ $line =~ "Logical devices/Failed/Degraded" ]] &&	CONTROLLER_DEVICES="${line#[[:space:]]*Logical devices/Failed/Degraded[[:space:]]*:[[:space:]]}"
	done

	IFS=$OLD_IFS

	local VOLUME_TOTAL=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f1)
	local VOLUME_FAILED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f2)
	local VOLUME_DEGRADED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f3)

	echo "В системе обнаружен RAID контроллер Adaptec: "
	echo ""

	rpad "Модель контроллера" 32 " : $CONTROLLER_MODEL\n"
	[[ $CONTROLLER_STATUS == "Optimal" ]] && rpad "Статус контроллера" 32 " : ${COLOR_GREEN}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"
	[[ $CONTROLLER_STATUS != "Optimal" ]] && rpad "Статус контроллера" 32 " : ${COLOR_RED}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"
	rpad "Температура" 32 " : $CONTROLLER_TEMPERATURE\n"
	rpad "Объем памяти" 32 " : $CONTROLLER_MEMORY\n"
	rpad "Режим производительности" 32 " : $CONTROLLER_PERFMODE\n"
	rpad "Кол-во массивов" 32 " : ${COLOR_GREEN}${VOLUME_TOTAL}${COLOR_NORMAL}\n"
	
	if [[ $VOLUME_DEGRADED -eq 0 ]]; then
		rpad "Кол-во деградированных массивов" 32 " : ${COLOR_GREEN}${VOLUME_DEGRADED}${COLOR_NORMAL}\n"
	else
		rpad "Кол-во деградированных массивов" 32 " : ${COLOR_RED}${VOLUME_DEGRADED}${COLOR_NORMAL}\n"
	fi

	if [[ $VOLUME_FAILED -eq 0 ]]; then
		rpad "Кол-во сбойных массивов" 32 " : ${COLOR_GREEN}${VOLUME_FAILED}${COLOR_NORMAL}\n"
	else
		rpad "Кол-во сбойных массивов" 32 " : ${COLOR_RED}${VOLUME_FAILED}${COLOR_NORMAL}\n"
	fi

	echo ""

	local volume VOLUME_DEVICE_NAME VOLUME_RAID_LEVEL VOLUME_STATUS VOLUME_SIZE VOLUME_READ_CACHE VOLUME_WRITE_CACHE VOLUME_HOT_SPARE

	for volume in $(seq 0 $(expr $VOLUME_TOTAL - 1)); do
		OLD_IFS=$IFS
		IFS=$'\n'

		for line in $(arcconf GETCONFIG 1 LD "$volume")
		do
			[[ $DEBUG == true ]] &&  debug $line

			[[ $line =~ "Logical Device name" ]] && VOLUME_DEVICE_NAME="${line#[[:space:]]*Logical Device name[[:space:]]*:[[:space:]]}"
			[[ $line =~ "RAID level" ]] && VOLUME_RAID_LEVEL="${line#[[:space:]]*RAID level[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Status of Logical Device" ]] && VOLUME_STATUS="${line#[[:space:]]*Status of Logical Device[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Size" ]] && VOLUME_SIZE="${line#[[:space:]]*Size[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Read-cache status" ]] && VOLUME_READ_CACHE="${line#[[:space:]]*Read-cache status[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Write-cache status" ]] && VOLUME_WRITE_CACHE="${line#[[:space:]]*Write-cache status[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Protected by Hot-Spare" ]] && VOLUME_HOT_SPARE="${line#[[:space:]]*Protected by Hot-Spare[[:space:]]*:[[:space:]]}"
		done

		echo ""
		rpad "Название массива" 32 ": ${VOLUME_DEVICE_NAME}\n"
		rpad "Уровень массива" 32 ": RAID ${VOLUME_RAID_LEVEL}\n"
		rpad "Размер массива" 32 ": ${VOLUME_SIZE}\n"
		[[ $VOLUME_STATUS == "Optimal" ]] && rpad "Состояние массива" 32 ": ${COLOR_GREEN}${VOLUME_STATUS}${COLOR_NORMAL}\n"
		[[ $VOLUME_STATUS != "Optimal" ]] && rpad "Состояние массива" 32 ": ${COLOR_RED}${VOLUME_STATUS}${COLOR_NORMAL}\n"
		[[ $VOLUME_READ_CACHE == "On" ]] && rpad "Кэш на чтение" 32 ": ${COLOR_GREEN}${VOLUME_READ_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_READ_CACHE != "On" ]] && rpad "Кэш на чтение" 32 ": ${COLOR_COLOR_YELLOW}${VOLUME_READ_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_WRITE_CACHE == "On" ]] && rpad "Кэш на запись" 32 ": ${COLOR_GREEN}${VOLUME_WRITE_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_WRITE_CACHE != "On" ]] && rpad "Кэш на запись" 32 ": ${COLOR_YELLOW}${VOLUME_WRITE_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_HOT_SPARE == "No" ]] && rpad "Защишен диском гор. замены" 32 ": ${COLOR_YELLOW}${VOLUME_HOT_SPARE}${COLOR_NORMAL}\n"
		[[ $VOLUME_HOT_SPARE != "No" ]] && rpad "Защишен диском гор. замены" 32 ": ${COLOR_GREEN}${VOLUME_HOT_SPARE}${COLOR_NORMAL}\n"

		local FPOS=$(expr $(arcconf GETCONFIG 1 LD "$volume" | grep -n "Logical Device segment information" | cut -d ':' -f 1) + 2)
		local LPOS=$(arcconf GETCONFIG 1 LD "$volume" | wc -l)

		echo ""
		echo "Перечень устройств массива"

		local filename="/tmp/${RANDOM}.random.txt"
		touch $filename

		echo -e "Шина\tУстройство\tИнтерфейс\tТип\tМодель\tРазмер" > $filename

		local pattern="[[:space:]]*Segment [0-9]*[[:space:]]*: Present \(([0-9]+)MB, ([A-Z]*), ([A-Z]*), Connector:([0-9]+), Device:([0-9]+)\)[[:space:]]*([0-9A-Z -]*)"
		local line

		while read line
		do
			if [[ $line =~ $pattern ]]; then
				echo -e "${BASH_REMATCH[4]}\t${BASH_REMATCH[5]}\t${BASH_REMATCH[2]}\t${BASH_REMATCH[3]}\t${BASH_REMATCH[6]}\t${BASH_REMATCH[1]}Mb" >> $filename
			fi
		done < <(arcconf GETCONFIG 1 LD "$volume" | sed -n ${FPOS},${LPOS}p)

		IFS=$OLD_IFS
		tput sgr0
		table_output $filename
		tput sgr0
	done

	echo "Убедитесь, что информация верна и отсутствуют ошибки"
	read -p  "сохранить данную конфигурацию Y/n"  -n 1 -r

	local $REPLY

	if [[ $REPLY =~ ^[Nn]$ ]]; then
		return
	fi

	echo ""
	echo "Controller Status: ${CONTROLLER_STATUS}" > $ADAPTEC_INIT_STATE

	local volume

	for volume in $(seq 0 $(expr $VOLUME_TOTAL - 1)); do
		OLD_IFS=$IFS
		IFS=$'\n'

		local line
		for line in $(arcconf GETCONFIG 1 LD "$volume"); do
			[[ $line =~ "Logical Device name" ]] && VOLUME_DEVICE_NAME="${line#[[:space:]]*Logical Device name[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Status of Logical Device" ]] && VOLUME_STATUS="${line#[[:space:]]*Status of Logical Device[[:space:]]*:[[:space:]]}"
		done

		IFS=$OLD_IFS
		echo "Volume: ${VOLUME_DEVICE_NAME}, Status: ${VOLUME_STATUS}" >> $ADAPTEC_INIT_STATE
	done

	echo "данные сохранены, ставим массив на мониторинг"
	echo ""
	echo "*/$CRONTAB_REFRESH_TIME * * * * root cd $CWD && ./jobs/adaptec.sh" > /etc/cron.d/adaptec-monitor
}


function hp_raid_check
{
	$(lockfile -r 2 var/run/hpacucli.lock > /dev/null)
	
	if [[ "$?" != "0" ]]; then
		echo "Запущен другой процесс hpacucli ($?)"
		exit 1
	fi

	echo "В системе обнаружен RAID контроллер" $(hpacucli ctrl all show detail | sed '2!d')

	if [[ $(which hpacucli | grep hpacucli -c ) -ne 1 ]]; then
		fail "в системе присутствуют RAID массивы но не установлен hpacucli"
		echo ""
		
		read -p "Скачать и установить hpacucli Y/n? " -n 1 -r

		local REPLY
		if [[ $REPLY =~ ^[Nn]$ ]]; then
			exit 1	
		fi

		install_raid_utils "HPUTILS"
	fi

	OLD_IFS=$IFS
	IFS=$'\n'

	local line CONTROLLER_SLOT CONTROLLER_STATUS CONTROLLER_WRITE_CACHE CONTROLLER_BATTERY CONTROLLER_CACHE_PRESENT CONTROLLER_CACHE_RATIO CONTROLLER_CACHE_SIZE

	for line in $(hpacucli ctrl all show detail)
	do
		[[ $DEBUG == true ]] && debug $line

		[[ $line =~ 'Slot:' ]] && CONTROLLER_SLOT="${line#[[:space:]]*Slot:[[:space:]]}"
		[[ $line =~ 'Firmware Version:' ]] && CONTROLLER_FIRMWARE="${line#[[:space:]]*Firmware Version:[[:space:]]}"
		[[ $line =~ 'Controller Status:' ]] && CONTROLLER_STATUS="${line#[[:space:]]*Controller Status:[[:space:]]}"
		[[ $line =~ 'Drive Write Cache:' ]] && CONTROLLER_WRITE_CACHE="${line#[[:space:]]*Drive Write Cache:[[:space:]]}"
		[[ $line =~ 'Battery/Capacitor Status:' ]] && CONTROLLER_BATTERY="${line#[[:space:]]*Battery/Capacitor Status:[[:space:]]}"
		[[ $line =~ 'Cache Board Present:' ]] && CONTROLLER_CACHE_PRESENT="${line#[[:space:]]*Cache Board Present:[[:space:]]}"
		[[ $line =~ 'Cache Ratio:' ]] && CONTROLLER_CACHE_RATIO="${line#[[:space:]]*Cache Ratio:[[:space:]]}"
		[[ $line =~ 'Total Cache Size:' ]] && CONTROLLER_CACHE_SIZE="${line#[[:space:]]*Total Cache Size:[[:space:]]}"
		[[ $line =~ 'No-Battery Write Cache:' ]] && CONTROLLER_NO_BATTERY_WRITE_CACHE="${line#[[:space:]]*No-Battery Write Cache:[[:space:]]}"
	done

	echo ""
	rpad "Контроллер в слоте" 32 " : ${CONTROLLER_SLOT}\n"
	rpad "Версия прошивки" 32 " : ${CONTROLLER_FIRMWARE}\n"
	
	[[ $CONTROLLER_STATUS == "OK" ]] && rpad "Статус контроллера" 32 " : ${COLOR_GREEN}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"
	[[ $CONTROLLER_STATUS != "OK" ]] && rpad "Статус контроллера" 32 " : ${COLOR_GREEN}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"

	[[ $CONTROLLER_CACHE_PRESENT == "True" ]] && rpad "Кэш память присутствует" 32 " : ${COLOR_GREEN}${CONTROLLER_WRITE_CACHE}${COLOR_NORMAL}\n"
	[[ $CONTROLLER_CACHE_PRESENT != "True" ]] && rpad "Кэш память присутствует" 32 " : ${COLOR_YELLOW}${CONTROLLER_WRITE_CACHE}${COLOR_NORMAL}\n"

	[[ -n $CONTROLLER_CACHE_SIZE ]] && rpad "Размер кэш памяти" 32 " : ${CONTROLLER_CACHE_SIZE}\n"

	[[ $CONTROLLER_WRITE_CACHE == "Disabled" ]] && rpad "Кэш на запись" 32 " : ${COLOR_YELLOW}${CONTROLLER_WRITE_CACHE}${COLOR_NORMAL}\n"
	[[ $CONTROLLER_WRITE_CACHE != "Disabled" ]] && rpad "Кэш на запись" 32 " : ${COLOR_GREEN}${CONTROLLER_WRITE_CACHE}${COLOR_NORMAL}\n"

	[[ -n $CONTROLLER_CACHE_RATIO ]] && rpad "Распределение кэш памяти" 32 " : ${CONTROLLER_CACHE_RATIO}\n"

	[[ $CONTROLLER_BATTERY == "OK" ]] && rpad "Статус батареи" 32 " : ${COLOR_GREEN}${CONTROLLER_BATTERY}${COLOR_NORMAL}\n"	
	[[ $CONTROLLER_BATTERY != "OK" ]] && rpad "Статус батареи" 32 " : ${COLOR_YELLOW}${CONTROLLER_BATTERY}${COLOR_NORMAL}\n"

	[[ -n $CONTROLLER_NO_BATTERY_WRITE_CACHE ]] && rpad "Кэш на запись без батареи" 32 " : ${CONTROLLER_NO_BATTERY_WRITE_CACHE}\n" 

	declare -a files
	local volume
	local count=0

	for volume in $(hpacucli ctrl slot=$CONTROLLER_SLOT ld all show | grep logicaldrive | sed -re "s/\s{2,}//" | cut -d" " -f2)
	do
		local volume_filename="/tmp/${RANDOM}.random.txt"
		touch $volume_filename

		files[count]=$volume_filename

		local line VOLUME_NUMBER VOLUME_SIZE VOLUME_LEVEL VOLUME_STATUS VOLUME_NAME

		for line in $(hpacucli ctrl slot=${CONTROLLER_SLOT} ld ${volume} show | sed -re "s/\s{2,}//")
		do
			[[ $DEBUG == true ]] && debug $line

			[[ $line == "Logical Drive:"* ]]   && VOLUME_NUMBER="${line#Logical Drive:[[:space:]]}"
			[[ $line == "Size:"* ]]            && VOLUME_SIZE="${line#Size:[[:space:]]}"
			[[ $line == "Fault Tolerance:"* ]] && VOLUME_LEVEL="${line#Fault Tolerance:[[:space:]]}"
			[[ $line == "Status:"* ]]          && VOLUME_STATUS="${line#Status:[[:space:]]}"
			[[ $line == "Disk Name:"* ]]       && VOLUME_NAME="${line#Disk Name:[[:space:]]}"
		done

		echo ""
		rpad "Номер массива" 32 " : $VOLUME_NUMBER\n"
		rpad "Уровень массива" 32 " : $VOLUME_LEVEL\n"
			
		rpad "Статус" 32 " : "
		[[ $VOLUME_STATUS == "OK" ]] && ok "$VOLUME_STATUS\n"
		[[ $VOLUME_STATUS != "OK" ]] && fail "$VOLUME_STATUS\n"

		rpad "Размер массива" 32 " : $VOLUME_SIZE\n"
		rpad "Название диска" 32 " : $VOLUME_NAME\n"

		VOLUME_SPARE=$(hp_get_spair_device $CONTROLLER_SLOT $VOLUME_NUMBER)

		[[ $VOLUME_SPARE == "0" ]] && rpad "Кол-во дисков гор. замены" 32 " : ${COLOR_YELLOW}${VOLUME_SPARE}${COLOR_NORMAL}\n"
		[[ $VOLUME_SPARE != "0" ]] && rpad "Кол-во дисков гор. замены" 32 " : ${COLOR_GREEN}${VOLUME_SPARE}${COLOR_NORMAL}\n"
		
		echo "${VOLUME_NUMBER};${VOLUME_LEVEL};${VOLUME_STATUS};${VOLUME_SPARE}" > $volume_filename

		local filename="/tmp/${RANDOM}.random.txt"
		touch $filename

		echo -e "Номер\tТип диска\tМодель\tСерийный номер\tРазмер\tСтатус" > $filename

		local devices

		for devices in $(hpacucli ctrl slot=$CONTROLLER_SLOT pd all show | sed -re "s/\s{2,}//" | grep -v "^$")
		do
			[[ $DEBUG == true ]] && debug $devices

    		if [[ $devices == "array"* ]]; then
        		local name=${devices#array[[:space:]]}
        		local num=$(expr $(ord $name) - 64)
    		fi

    		if [[ $num -eq $VOLUME_NUMBER && $devices =~ "physicaldrive" ]]; then
        		local harddrive=$(echo "$devices" | awk '{ print $2 }')
        		
        		for info in $(hpacucli ctrl slot=$CONTROLLER_SLOT pd $harddrive show | sed -re "s/\s{2,}//" | grep -v "^$")
        		do
					[[ $DEBUG == true ]] && debug $info

					[[ $info =~ "physicaldrive" ]]   && DEVICE_PORT="${info#physicaldrive[[:space:]]}"
					[[ $info =~ "Status:" ]]         && DEVICE_STATUS="${info#Status:[[:space:]]}"
					[[ $info =~ "Drive Type:" ]]     && DEVICE_TYPE="${info#Drive Type:[[:space:]]}"
					[[ $info =~ "Size:" ]]           && DEVICE_SIZE="${info#Size:[[:space:]]}"
					[[ $info =~ "Model:" ]]          && DEVICE_MODEL="${info#Model:[[:space:]]}"
					[[ $info =~ "Serial Number:" ]]  && DEVICE_SERIAL="${info#Serial Number:[[:space:]]}"

					DEVICE_MODEL=$(echo $DEVICE_MODEL | sed -re "s/^\s*//; s/\s{2,}/ /")
					DEVICE_SERIAL=$(echo $DEVICE_SERIAL | sed -re "s/^\s*//; s/\s{2,}/ /")
				done

				if [[ $DEVICE_STATUS == "Failed" ]]; then
					DEVICE_STATUS="${COLOR_RED}${DEVICE_STATUS}${COLOR_NORMAL}"
					DEVICE_TYPE="Drive Offline"
				elif [[ $DEVICE_STATUS == "Rebuilding" ]]; then
					DEVICE_STATUS="${COLOR_YELLOW}${DEVICE_STATUS}${COLOR_NORMAL}"
				fi


				[[ $DEBUG == true ]] && echo ""
				echo -e "$DEVICE_PORT\t$DEVICE_TYPE\t$DEVICE_MODEL\t$DEVICE_SERIAL\t$DEVICE_SIZE\t$DEVICE_STATUS" >> $filename
				echo "${DEVICE_PORT};${DEVICE_TYPE};${DEVICE_MODEL};${DEVICE_SERIAL};${DEVICE_SIZE};${DEVICE_STATUS}" >> $volume_filename
			fi
		done

		tput sgr0
		table_output $filename
		tput sgr0

		count=$(( $count + 1 ))
	done

	rm -f var/run/hpacucli.lock

	if [[ $1 == "REPORT" ]]; then
		return
	fi

	if [[ $AUTO_ANSWER == "no" ]]; then
		echo "Убедитесь, что информация верна и отсутствуют ошибки"
		read -p  "сохранить данную конфигурацию Y/n"  -n 1 -r

		local $REPLY

		if [[ $REPLY =~ ^[Nn]$ ]]; then
			return
		fi
	fi

	rm -f $HP_INIT_STATE/*
	echo ""
	count=0

	while [ "x${files[count]}" != "x" ]
	do
		cp ${files[count]} $HP_INIT_STATE/volume.${count}
   		count=$(( $count + 1 ))
	done

	echo "данные сохранены, ставим массив на мониторинг"
	echo ""
	echo "*/$CRONTAB_REFRESH_TIME * * * * root cd $CWD && ./jobs/hp_smartarray.sh" > /etc/cron.d/hp_smartarray-monitor

	IFS=$OLD_IFS
}

function hp_make_report
{
	hp_raid_check "REPORT"
}

function hp_get_spair_device
{
	CONTROLLER_SLOT=$1
	VOLUME_NUMBER=$2
	TOTAL_SPARE=0

	local devices

	for devices in $(hpacucli ctrl slot=$CONTROLLER_SLOT pd all show | sed -re "s/\s{2,}//" | grep -v "^$")
	do
		[[ $DEBUG == true ]] && debug $devices

		if [[ $devices == "array"* ]]; then
    		local name=${devices#array[[:space:]]}
    		local num=$(expr $(ord $name) - 64)
		fi

		if [[ $num -eq $VOLUME_NUMBER && $devices =~ "physicaldrive" ]]; then
    		TOTAL_SPARE=$(( $TOTAL_SPARE + $(echo "$devices" | grep -c "spare") ))
		fi
	done

	echo $TOTAL_SPARE
}

function hp_check_volume_status
{
	echo $(hpacucli ctrl slot=$1 ld $2 show status | grep -v "^$" | sed -re "s/\s+//" | awk -F": " '{print $2}')
}

function hp_check_disk_status
{
	echo $(hpacucli ctrl slot=$1 pd $2 show status | grep -v "^$" | sed -re "s/\s+//" | awk -F": " '{print $2}')
}

function hp_get_drive_type
{
	local line DEVICE_TYPE

	for line in $(hpacucli ctrl slot=$1 pd $2 show | grep -v "^$" | sed -re "s/\s{2,}//")	
	do
		[[ $line =~ "Drive Type:" ]] && DEVICE_TYPE="${line#Drive Type:[[:space:]]}"
	done

	echo $DEVICE_TYPE
}

function hp_get_drive_serial
{
	local line DEVICE_SERIAL

	for line in $(hpacucli ctrl slot=$1 pd $2 show | grep -v "^$" | sed -re "s/\s{2,}//")	
	do
		[[ $line =~ "Serial Number:" ]] && DEVICE_SERIAL="${line#Serial Number:[[:space:]]}"
	done

	DEVICE_SERIAL=$(echo $DEVICE_SERIAL | sed -re "s/^\s*//; s/\s{2,}/ /")

	echo $DEVICE_SERIAL
}


function hp_get_volume_type
{
	echo $(hpacucli ctrl slot=$1 ld $2 show | grep "Fault Tolerance:" | sed -re "s/^\s*//" | awk -F": " '{print $2}')
}