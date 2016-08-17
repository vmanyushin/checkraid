#!/bin/bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

OLD_CWD=$(pwd)
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $CWD

. ../lib/vars.sh
. ../lib/functions.sh
. ../lib/utils.sh

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
	send_notify "Обнаружен сбой в RAID контроллере" "Статус RAID контроллера: $CONTROLLER_STATUS"
	EXIT_STATUS=1
fi

if [[ $CACHE_STATUS != "OK" ]]; then
	logger -t raid-tools "Статус кэша RAID контроллера '${CACHE_STATUS}'"
	send_notify "Обнаружен сбой в кэше RAID контроллере" "Статус кэша RAID контроллера: $CACHE_STATUS"
	EXIT_STATUS=1
fi

if [[ $BATTERY_STATUS != "OK" ]]; then
	logger -t raid-tools "Статус батареи RAID контроллера '${BATTERY_STATUS}'"
	send_notify "Обнаружен сбой в батарее RAID контроллере" "Статус батареи RAID контроллера: $BATTERY_STATUS"
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

			status=$(hp_check_volume_status $CONTROLLER_SLOT ${volume[0]} ${volume[1]})
			[[ $DEBUG == true ]] && debug "hp_check_volume_status $CONTROLLER_SLOT ${volume[0]} ${volume[1]} = $status"
			
			if [[ $status == "1" ]]; then
				subj="Ошибка в дисковом массиве"
				mesg="Номер массива: ${volume[0]}, Уровень массива: ${volume[1]}, Статус массива: ${volume[2]}"

				logger -t raid-tools "$subj $mesg"
				send_notify $subj $mesg
				
				EXIT_STATUS=1
			elif [[ $status == "2" ]]; then
				volume_type=$(hp_get_volume_type $CONTROLLER_SLOT ${volume[1]})

				subj="Уровень RAID массива изменился"
				mesg="Номер массива: ${volume[0]}, Уровень массива указанные в конфигурации: ${volume[1]}, актуальный: $volume_type"

				logger -t raid-tools "$subj $mesg"
				send_notify $subj $mesg
				
				EXIT_STATUS=1
			fi
		fi

		if [[ $count -gt 0 ]]; then
			IFS=';' read -r -a disk <<< "$line"
			status=$(hp_check_disk_status $CONTROLLER_SLOT ${disk[0]} ${disk[3]} ${disk[1]})
			[[ $DEBUG == true ]] && debug "hp_check_disk_status ${disk[0]} ${disk[3]} ${disk[1]} = $status"

			if [[ $status == "1" ]]; then
				subj="Обнаружена ошибка на жестком диске"
				mesg="Порт: ${disk[0]}, Тип диска: ${disk[1]}, Модель диска: ${disk[2]}, Серийный номер: ${disk[3]}, Статус диска: ${disk[5]}"

				logger -t raid-tools "$subj, $mesg"
				send_notify $subj $mesg
				
				EXIT_STATUS=1
			elif [[ $status == "2" ]]; then
				subj="Обнаружены изменения в конфигурации RAID массива"
				mesg="Серийный номер диска на порту ${disk[0]} не соответствует ранее сохраненному ${disk[3]}"

				logger -t raid-tools "$subj, $mesg"
				send_notify $subj $mesg

				EXIT_STATUS=1
			elif [[ $status == "3" ]]; then
				drive_type=$(hp_get_drive_type $CONTROLLER_SLOT ${disk[0]})

				subj="Обнаружены изменения в конфигурации RAID массива"
				mesg="Изменился тип диска на порту ${disk[0]}, Серийный номер ${disk[3]}, Тип диска указанный в конфигурации: ${disk[1]}, актуальный: $drive_type"

				logger -t raid-tools "$subj, $mesg"
				send_notify $subj $mesg

				EXIT_STATUS=1
			elif [[ $status == "4" ]]; then
				subj="Обнаружены изменения в конфигурации RAID массива"
				mesg="Диск подключенный на порт ${disk[0]} с серийным номером ${disk[3]} не найден"

				logger -t raid-tools "$subj, $mesg"
				send_notify $subj $mesg

				EXIT_STATUS=1
			fi
		fi

		count=$(( $count + 1 ))
	done
done

if [[ $EXIT_STATUS == "0" ]]; then
	send_notify "Ошибок не обнаружено" "Ошибок в массиве или дисках массива не обнаружено"
fi

IFS=$OLD_IFS
rm -f ../var/run/hpacucli.lock

cd $OLD_CWD
exit $EXIT_STATUS

