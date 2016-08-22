#!/bin/bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

OLD_CWD=$(pwd)
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $CWD

. ../lib/vars.sh
. ../lib/functions.sh
. ../lib/utils.sh

OLD_IFS=$IFS
IFS=$'\n'

exit_status=""
DEBUG=false

while getopts ":d" opt
do
	case $opt in
		d) DEBUG=true  ;; # включаем режим отдадки
	esac
done

for line in $(arcconf GETCONFIG 1 AD)
do
	[[ $DEBUG == true ]] && debug $line
	[[ $line =~ "Controller Status" ]] && controller_status="${line#[[:space:]]*Controller Status[[:space:]]*:[[:space:]]}"
	[[ $line =~ "Logical devices/Failed/Degraded" ]] &&	controller_devices="${line#[[:space:]]*Logical devices/Failed/Degraded[[:space:]]*:[[:space:]]}"
	[[ $line =~ "Defunct disk drive count" ]] && controller_defunc_drives="${line#[[:space:]]*Defunct disk drive count[[:space:]]*:[[:space:]]}"
done

volume_total=$(echo "$controller_devices" | cut -d"/" -f1)
volume_failed=$(echo "$controller_devices" | cut -d"/" -f2)
volume_degraded=$(echo "$controller_devices" | cut -d"/" -f3)

[[ $volume_failed -ne 0 ]] && exit_status=1
[[ $volume_degraded -ne 0 ]] && exit_status=1
[[ $controller_defunc_drives -gt 0 ]] && exit_status=1

for volume_file in $(ls $ADAPTEC_INIT_STATE/*)
do
	[[ $volume_file == ".gitignore" ]] && continue
	[[ $DEBUG == true ]] && debug $volume_file
	count=0

	declare -a volume
	declare -a disk

	for line in $(cat $volume_file)
	do
		[[ $DEBUG == true ]] && debug $line

		if [[ $count -eq 0 ]]; then
			#
			# 1;r10;10;95190 MB;Degraded, Rebuilding ( Rebuild : 43 % )
			# volume[0] = номер массива
			# volume[1] = название массива
			# volume[2] = уровень
			# volume[3] = размер
			# volume[4] = статус
			#
			IFS=';' read -r -a volume <<< "$line"

			name=$(adaptec_get_volume_name ${volume[0]})
			[[ "$name" != "${volume[1]}" ]] && exit_status=${exit_status:-2}

			level=$(adaptec_get_volume_level ${volume[0]})
			[[ "$level" != "${volume[2]}" ]] && exit_status=${exit_status:-2}

			size=$(adaptec_get_volume_size ${volume[0]})
			[[ "$size" != "${volume[3]}" ]] && exit_status=${exit_status:-2}
		fi

		if [[ $count -gt 0 ]]; then
			#
			# 1,0;OCZ-VERTEX2;OCZ-65332S9S7K13ZY94;47703 MB;Online
			# disk[0] = шина, порт
			# disk[1] = модель
			# disk[2] = серийный номер
			# disk[3] = размер
			# disk[4] = статус
			#
			IFS=';' read -r -a disk <<< "$line"
			con=${disk[0]:0:1}
			dev=${disk[0]:2:1}

			#
			# drive_info[0] = шина
			# drive_info[1] = номер устройства
			# drive_info[2] = модель
			# drive_info[3] = серийный номер
			# drive_info[4] = размер
			# drive_info[5] = состояние
			#
			IFS=',' read -r -a drive_info <<< "$(arcconf GETCONFIG 1 PD | awk -v con=$con -v dev=$dev -f ../lib/adaptec_get_driveinfo.awk)"

			[[ "${disk[1]}" != "${drive_info[2]}" ]] && exit_status=${exit_status:-2}
			[[ "${disk[2]}" != "${drive_info[3]}" ]] && exit_status=${exit_status:-2}
			[[ "${disk[3]}" != "${drive_info[4]}" ]] && exit_status=${exit_status:-2}
			[[ "${disk[4]}" != "${drive_info[5]}" ]] && exit_status=${exit_status:-2}
		fi

		count=$(( count + 1 ))
	done
done

sleep 1 && cd ..
CWD="$( pwd )"

[[ $DEBUG == "true" ]] && debug "exit_status = $exit_status"

if [[ $exit_status == "1" ]]; then
	[[ ! -f $VARDIR/adaptec/.error ]] && touch $VARDIR/adaptec/.error
	subject="На сервере $(get_primary_ip_address) обнаружены ошибки в RAID массиве"
 	message=$(adaptec_raid_check "REPORT")
 	report="tmp/${RANDOM}.report.txt"
 	echo "$message" | lib/ansi2html.sh > $report
 	send_notify $subject $report
elif [[ $exit_status == "2" ]]; then
	AUTO_ANSWER="yes"
 	$(adaptec_raid_check > /dev/null)
else
	if [[ -f $VARDIR/adaptec/.error ]]; then
		rm -f $VARDIR/adaptec/.error
		subject="На сервере $(get_primary_ip_address) ошибки в RAID массиве устаранены"
 		message=$(adaptec_raid_check "REPORT")
 		report="tmp/${RANDOM}.report.txt"
 		echo "$message" | lib/ansi2html.sh > $report
 		send_notify $subject $report
	fi
fi

cd $OLD_CWD
exit $exit_status

