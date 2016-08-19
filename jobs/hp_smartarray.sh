#!/bin/bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

OLD_CWD=$(pwd)
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $CWD

. ../lib/vars.sh
. ../lib/functions.sh
. ../lib/utils.sh
. ../lib/test_functions.sh

EXIT_STATUS=0
DEBUG=false

while getopts ":d" opt
do
	case $opt in
		d) DEBUG=true  ;; # включаем режим отдадки
	esac
done

lockfile -r 2 ../var/run/hpacucli.lock

if [[ $? -ne 0 ]]; then
	echo "Запущен другой процесс hpacucli"
	exit 73
fi

OLD_IFS=$IFS
IFS=$'\n'

for line in $(hpacucli ctrl all show detail)
do
	[[ $DEBUG == true ]] && debug $line
	[[ $line =~ 'Slot:' ]] && CONTROLLER_SLOT="${line#[[:space:]]*Slot:[[:space:]]}"
done

for line in $(hpacucli ctrl slot=$CONTROLLER_SLOT show status | grep Status | sed -re 's/\s{2,}//')
do
	[[ $DEBUG == true ]] && debug $line
	[[ $line =~ "Controller Status:" ]] && CONTROLLER_STATUS="${line#Controller Status:[[:space:]]}"
	[[ $line =~ "Cache Status:" ]] && CACHE_STATUS="${line#Cache Status:[[:space:]]}"
	[[ $line =~ "Battery/Capacitor Status:" ]] && BATTERY_STATUS="${line#Battery/Capacitor Status:[[:space:]]}"
done

if [[ $CONTROLLER_STATUS != "OK" ]]; then
	logger -t raid-tools "Статус RAID контроллера '${CONTROLLER_STATUS}'"
	EXIT_STATUS=1
fi

if [[ $CACHE_STATUS != "OK" ]]; then
	logger -t raid-tools "Статус кэша RAID контроллера '${CACHE_STATUS}'"
	EXIT_STATUS=1
fi

if [[ $BATTERY_STATUS != "OK" ]]; then
	logger -t raid-tools "Статус батареи RAID контроллера '${BATTERY_STATUS}'"
	EXIT_STATUS=1
fi

for volume_file in $(ls $HP_INIT_STATE/*)
do
	[[ $DEBUG == true ]] && debug $volume_file
	count=0

	declare -a volume
	declare -a disk

	for line in $(cat $volume_file)
	do
		[[ $DEBUG == true ]] && debug $line

		if [[ $count -eq 0 ]]; then
			IFS=';' read -r -a volume <<< "$line"

			# для тестирования
			# status=$(test_hp_check_volume_status $CONTROLLER_SLOT ${volume[0]} ${volume[1]})
			status=$(hp_check_volume_status $CONTROLLER_SLOT ${volume[0]} ${volume[1]})
			[[ $DEBUG == true ]] && debug "hp_check_volume_status $CONTROLLER_SLOT ${volume[0]} ${volume[1]} = $status"
			
			if [[ $status != "OK" ]]; then
				subj="Ошибка в дисковом массиве"
				mesg="Номер массива: ${volume[0]}, Уровень массива: ${volume[1]}, Статус массива: $status"
				logger -t raid-tools "$subj $mesg"			
				EXIT_STATUS=1
			fi

			# для тестирования
			# volume_type=$(test_hp_get_volume_type $CONTROLLER_SLOT ${volume[0]})
			volume_type=$(hp_get_volume_type $CONTROLLER_SLOT ${volume[0]})

			if [[ $volume_type != "${volume[1]}" ]]; then
				subj="Уровень RAID массива изменился"
				mesg="Номер массива: ${volume[0]}, Уровень массива указанные в конфигурации: ${volume[1]}, актуальный: $volume_type"
				logger -t raid-tools "$subj $mesg"
				EXIT_STATUS=1
			fi
		fi

		if [[ $count -gt 0 ]]; then
			IFS=';' read -r -a disk <<< "$line"

			# для тестирования
			# status=$(test_hp_check_disk_status $CONTROLLER_SLOT ${disk[0]} ${disk[3]} ${disk[1]})
			status=$(hp_check_disk_status $CONTROLLER_SLOT ${disk[0]} ${disk[3]} ${disk[1]})

			[[ $DEBUG == true ]] && debug "hp_check_disk_status ${disk[0]} ${disk[3]} ${disk[1]} = $status"

			if [[ $status != "OK" ]]; then
				EXIT_STATUS=1
			fi

			# для тестирования
			# serial=$(test_hp_get_drive_serial $CONTROLLER_SLOT ${disk[0]})
			serial=$(hp_get_drive_serial $CONTROLLER_SLOT ${disk[0]})

			if [[ $serial != "${disk[3]}" ]]; then
				EXIT_STATUS=${EXIT_STATUS:-2}
			fi

			# для тестирования
			# drive_type=$(test_hp_get_drive_type $CONTROLLER_SLOT ${disk[0]})
			drive_type=$(hp_get_drive_type $CONTROLLER_SLOT ${disk[0]})

			if [[ $drive_type != "${disk[1]}" ]]; then
				EXIT_STATUS=${EXIT_STATUS:-2}
			fi
		fi

		count=$(( $count + 1 ))
	done
done

IFS=$OLD_IFS
rm -f ../var/run/hpacucli.lock

sleep 1 && cd ..

[[ $DEBUG == "true" ]] && debug "EXIT_STATUS = $EXIT_STATUS"

if [[ $EXIT_STATUS == "1" ]]; then
	
 	message=$(hp_make_report)
 	report="tmp/${RANDOM}.report.txt"
 	echo "$message" | lib/ansi2html.sh > $report
 	send_notify "Обнаружены ошибки в RAID массиве" $report
 elif [[ $EXIT_STATUS == "2" ]]; then
 	AUTO_ANSWER="yes"
 	hp_raid_check 
fi

cd $OLD_CWD
exit $EXIT_STATUS

