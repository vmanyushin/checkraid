#!/bin/bash
#
# created: 04.08.2016
# updated: 
# author: vmanyushin@gmail.com
# version: 0.1
# description:
#

function os_detect
{
	[[ $DEBUG == true ]] && debug "runnig os_detect()"

	DIST_FAMILY=''
	DIST_NAME=''
	DIST_VERSION=''
	DIST_ARCH=''

	[[ -e "/usr/bin/yum" || -e "/bin/rpm" ]] && DIST_FAMILY='RedHat'
	[[ -e "/usr/bin/apt" || -e "/usr/bin/apt-get" || -e "/usr/bin/dpkg" ]] && DIST_FAMILY='Debian'

	[[ $DEBUG == true ]] && debug "DIST_FAMILY  = ${DIST_FAMILY}"

	case "$DIST_FAMILY" in
		"RedHat" )
		if [[ -e /etc/redhat-release ]]; then
			DIST_NAME=$(grep -Po '^(\w+)' /etc/redhat-release)
			DIST_VERSION=$(grep -Po '[0-9]+\.[0-9]+' /etc/redhat-release)
		fi
		;;
		"Debian" )
		if [[ -e /etc/lsb-release ]]; then
			source /etc/lsb-release
			DIST_NAME=$DISTRIB_ID
			DIST_VERSION=$DISTRIB_RELEASE
		elif [[ $(which lsb_release | grep lsb_release -c) -eq 1 ]]; then
			DIST_NAME=$(lsb_release -a 2>/dev/null | grep Codename | cut -d":" -f 2 | tr -d "[[:space:]]")
			DIST_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${DIST_NAME:0:1})${DIST_NAME:1}"
			DIST_VERSION=$(lsb_release -a 2>/dev/null | grep Release | cut -d ":" -f 2 | tr -d "[[:space:]]")
		fi
		;;
	esac

	[[ $DEBUG == true ]] && debug "DIST_NAME    = ${DIST_NAME}"
	[[ $DEBUG == true ]] && debug "DIST_VERSION = ${DIST_VERSION}"

	DIST_ARCH=$(arch)

	[[ $DEBUG == true ]] && debug "DIST_ARCH    = ${DIST_ARCH}"
}

function detect_raid_controller
{
	[[ -e /proc/mdstat && $(cat /proc/mdstat | grep ^md -c) -gt 0 ]] && RAID_SOFTWARE=true
	[[ $(lspci | grep -i adaptec -c ) -gt 0 ]] && RAID_ADAPTEC=true
	[[ $(lspci | grep -i 'Hewlett-Packard' | grep -i 'Smart Array' -c ) -gt 0 ]] && RAID_HP=true
	[[ $(lspci | grep -i lsi -c ) -gt 0 ]] && RAID_LSI=true
	[[ $(lspci | grep -i 3ware -c ) -gt 0 ]] && RAID_3WARE=true

	[[ $DEBUG == true ]] && debug "RAID_SOFTWARE = ${RAID_SOFTWARE}"
	[[ $DEBUG == true ]] && debug "RAID_ADAPTEC  = ${RAID_ADAPTEC}"
	[[ $DEBUG == true ]] && debug "RAID_HP       = ${RAID_HP}"
	[[ $DEBUG == true ]] && debug "RAID_LSI      = ${RAID_LSI}"
	[[ $DEBUG == true ]] && debug "RAID_3WARE    = ${RAID_3WARE}"
}

function debug
{
	echo -e "${COLOR_YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]: DEBUG $1${COLOR_NORMAL}"
}

function echo_ok
{
	echo -ne "${COLOR_GREEN}$1${COLOR_NORMAL}"
}

function echo_fail
{
	echo -ne "!!! ${COLOR_RED}$1 ${COLOR_NORMAL}!!!"
}

function software_raid_check
{
	if [[ $(which mdadm | grep mdadm -c ) -ne 1 ]]; then
		echo_fail "в системе присутствуют RAID массивы но не установлен mdadm"
		echo ""
		return
	fi

	RAID_DEVICES=$(grep ^md -c /proc/mdstat)
	[[ $DEBUG == true ]] && debug "total RAID devices = ${RAID_DEVICES}"

	if [[ $RAID_DEVICES == 0 ]]; then 
		return
	fi

	if [[ $RAID_DEVICES > 0 ]]; then
		echo "В системе обнаружен SOFTRAID"
		echo -n "Количество RAID массивов в системе = "
		echo_ok "${RAID_DEVICES}" 
		echo ""
	fi

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

    	RAID_NAME=$(mdadm --detail $name | head -n 1 | cut -d '/' -f 3 | cut -d ':' -f 1)
    	RAID_LEVEL=$(mdadm --detail $name | grep 'Raid Level' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_SIZE=$(( $(mdadm --detail $name | grep 'Array Size' | cut -d ':' -f 2 | cut -d ' ' -f 2 | tr -d '[[:space:]]') / 1024 ))
    	RAID_ACTIVE_DEVICES=$(mdadm --detail $name | grep 'Raid Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_WORKING_DEVICES=$(mdadm --detail $name | grep 'Working Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_FAILED_DEVICES=$(mdadm --detail $name | grep 'Failed Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_SPARE_DEVICES=$(mdadm --detail $name | grep 'Spare Devices' | cut -d ':' -f 2 | tr -d '[[:space:]]')
    	RAID_STATUS=$(mdadm --detail $name | grep 'State :' | cut -d ':' -f 2 | tr -d '[[:space:]]')


    	echo ""
		echo "      Название устройства : ${RAID_NAME}"
		echo "             Типа массива : ${RAID_LEVEL}"
		echo "           Размер массива : ${RAID_SIZE}Mb"
		echo "            Кол-во дисков : ${RAID_ACTIVE_DEVICES}"
		echo " Кол-во работающих дисков : ${RAID_WORKING_DEVICES}" 
		echo "Кол-во дисков гор. замены : ${RAID_SPARE_DEVICES}"

		echo -n "    Кол-во сбойных дисков : "; 
		if [[ $RAID_FAILED_DEVICES > 0 ]]; then 
			echo_fail $RAID_FAILED_DEVICES
			echo ""
		else
			echo $RAID_FAILED_DEVICES
			echo ""
		fi

		echo -n "           Статус массива : "; 
		if [[ $RAID_STATUS == "clean" ]]; then
			echo_ok $RAID_STATUS
		else
			echo_fail $RAID_STATUS
		fi

		echo ""

		FPOS=$(expr `mdadm --detail $name | grep -n RaidDevice | cut -d ':' -f 1` + 1)
		LPOS=$(mdadm --detail $name | wc -l)

		echo ""
		echo "Статус устройств массива"

		filename="/tmp/${RANDOM}.random.txt"
		touch $filename

		echo -e "Устройство\tСинхронизирован\tСтатус" > $filename

		while read number major minor device state 
		do
			status=(${state// / })
			
			dev_state=${status[0]}
			dev_sync=${status[1]}
			dev_name=${status[2]}

			[[ $dev_state == "active" ]] && dev_state="\033[0;32m${dev_state}\e[0m"
			[[ $dev_state != "active" ]] && dev_state="\033[0;31m${dev_state}\e[0m"

			echo -e "${dev_name}\t${dev_sync}\t${dev_state}" >> $filename
		done < <(mdadm --detail $name | sed -n ${FPOS},${LPOS}p)

		tput sgr0
		table_output $filename
		tput sgr0

		IFS=$OLD_IFS

	done < <(mdadm --detail --scan)

	echo "Убедитесь, что информация верна и отсутствуют ошибки"
	read -p  "сохранить данную конфигурацию Y/n"  -n 1 -r

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
	echo "*/1 * * * * root cd $CWD && ./softraid-mon.sh" > /etc/cron.d/softraid-mon
}

function adaptec_raid_check
{
	if [[ $(which arcconf | grep arcconf -c ) -ne 1 ]]; then
		echo_fail "в системе присутствуют RAID массивы но не установлен arcconf"
		echo ""
		
		read -p "Скачать и установить arcconf Y/n? " -n 1 -r
		if [[ $REPLY =~ ^[Nn]$ ]]; then
			exit 1	
		fi

		install_arcconf
	fi


	OLD_IFS=$IFS
	IFS=$'\n'

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

	VOLUME_TOTAL=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f1)
	VOLUME_FAILED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f2)
	VOLUME_DEGRADED=$(echo "$CONTROLLER_DEVICES" | cut -d"/" -f3)

	echo "В системе обнаружен RAID контроллер Adaptec: "
	echo ""

	lpad "Модель контроллера" 32 " : $CONTROLLER_MODEL\n"
	[[ $CONTROLLER_STATUS == "Optimal" ]] && lpad "Статус контроллера" 32 " : ${COLOR_GREEN}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"
	[[ $CONTROLLER_STATUS != "Optimal" ]] && lpad "Статус контроллера" 32 " : ${COLOR_RED}${CONTROLLER_STATUS}${COLOR_NORMAL}\n"
	lpad "Температура" 32 " : $CONTROLLER_TEMPERATURE\n"
	lpad "Объем памяти" 32 " : $CONTROLLER_MEMORY\n"
	lpad "Режим производительности" 32 " : $CONTROLLER_PERFMODE\n"
	lpad "Кол-во массивов" 32 " : ${COLOR_GREEN}${VOLUME_TOTAL}${COLOR_NORMAL}\n"
	
	if [[ $VOLUME_DEGRADED -eq 0 ]]; then
		lpad "Кол-во деградированных массивов" 32 " : ${COLOR_GREEN}${VOLUME_DEGRADED}${COLOR_NORMAL}\n"
	else
		lpad "Кол-во деградированных массивов" 32 " : ${COLOR_RED}${VOLUME_DEGRADED}${COLOR_NORMAL}\n"
	fi

	if [[ $VOLUME_FAILED -eq 0 ]]; then
		lpad "Кол-во сбойных массивов" 32 " : ${COLOR_GREEN}${VOLUME_FAILED}${COLOR_NORMAL}\n"
	else
		lpad "Кол-во сбойных массивов" 32 " : ${COLOR_RED}${VOLUME_FAILED}${COLOR_NORMAL}\n"
	fi

	echo ""

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
		lpad "Название массива" 32 ": ${VOLUME_DEVICE_NAME}\n"
		lpad "Уровень массива" 32 ": RAID ${VOLUME_RAID_LEVEL}\n"
		lpad "Размер массива" 32 ": ${VOLUME_SIZE}\n"
		[[ $VOLUME_STATUS == "Optimal" ]] && lpad "Состояние массива" 32 ": ${COLOR_GREEN}${VOLUME_STATUS}${COLOR_NORMAL}\n"
		[[ $VOLUME_STATUS != "Optimal" ]] && lpad "Состояние массива" 32 ": ${COLOR_RED}${VOLUME_STATUS}${COLOR_NORMAL}\n"
		[[ $VOLUME_READ_CACHE == "On" ]] && lpad "Кэш на чтение" 32 ": ${COLOR_GREEN}${VOLUME_READ_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_READ_CACHE != "On" ]] && lpad "Кэш на чтение" 32 ": ${COLOR_COLOR_YELLOW}${VOLUME_READ_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_WRITE_CACHE == "On" ]] && lpad "Кэш на запись" 32 ": ${COLOR_GREEN}${VOLUME_WRITE_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_WRITE_CACHE != "On" ]] && lpad "Кэш на запись" 32 ": ${COLOR_YELLOW}${VOLUME_WRITE_CACHE}${COLOR_NORMAL}\n"
		[[ $VOLUME_HOT_SPARE == "No" ]] && lpad "Защишен диском гор. замены" 32 ": ${COLOR_YELLOW}${VOLUME_HOT_SPARE}${COLOR_NORMAL}\n"
		[[ $VOLUME_HOT_SPARE != "No" ]] && lpad "Защишен диском гор. замены" 32 ": ${COLOR_GREEN}${VOLUME_HOT_SPARE}${COLOR_NORMAL}\n"

		FPOS=$(expr $(arcconf GETCONFIG 1 LD "$volume" | grep -n "Logical Device segment information" | cut -d ':' -f 1) + 2)
		LPOS=$(arcconf GETCONFIG 1 LD "$volume" | wc -l)

		echo ""
		echo "Перечень устройств массива"

		filename="/tmp/${RANDOM}.random.txt"
		touch $filename

		echo -e "Шина\tУстройство\tИнтерфейс\tТип\tМодель\tРазмер" > $filename

		pattern="[[:space:]]*Segment [0-9]*[[:space:]]*: Present \(([0-9]+)MB, ([A-Z]*), ([A-Z]*), Connector:([0-9]+), Device:([0-9]+)\)[[:space:]]*([0-9A-Z -]*)"
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

	if [[ $REPLY =~ ^[Nn]$ ]]; then
		return
	fi

	echo ""
	echo "Controller Status: ${CONTROLLER_STATUS}" > $ADAPTEC_INIT_STATE

	for volume in $(seq 0 $(expr $VOLUME_TOTAL - 1)); do
		OLD_IFS=$IFS
		IFS=$'\n'

		for line in $(arcconf GETCONFIG 1 LD "$volume"); do
			[[ $line =~ "Logical Device name" ]] && VOLUME_DEVICE_NAME="${line#[[:space:]]*Logical Device name[[:space:]]*:[[:space:]]}"
			[[ $line =~ "Status of Logical Device" ]] && VOLUME_STATUS="${line#[[:space:]]*Status of Logical Device[[:space:]]*:[[:space:]]}"
		done

		IFS=$OLD_IFS
		echo "Volume: ${VOLUME_DEVICE_NAME}, Status: ${VOLUME_STATUS}" >> $ADAPTEC_INIT_STATE
	done

	echo "данные сохранены, ставим массив на мониторинг"
	echo ""
	echo "*/1 * * * * root cd $CWD && ./adaptec-mon.sh" > /etc/cron.d/adaptec-mon
}


function install_arcconf
{
	echo "Скачиваю arcconf"
	wget $ARCCONF_URL -O /usr/sbin/arcconf -o /dev/null

	if [[ ! -e /usr/sbin/arcconf ]]; then
		echo "Не удалось скачать arcconf, попробуйте установить его вручную"
		echo "ссылка на скачивание ${$ARCCONF_URL}"
		exit 1
	fi

	echo "arcconf установлен"
	chmod +x /usr/sbin/arcconf
}

function install_wget
{
	case "$DIST_FAMILY" in
	"RedHat" )
		yum install wget -y
	;;
	"Debian" )
		apt install wget -y
	;;
	esac

	if [[ $(which wget | grep wget -c ) -ne 1 ]]; then
		echo "wget не установлен? попробуйте установить его вручную"
		exit 1
	fi

}

function table_output
{
    echo ""
    sed -e 's/\t/_|_/g' $filename |  column -t -s '_' | awk '1;!(NR%1){print "--------------------------------------------------------------------------------------";}'
    echo ""

    rm $filename
}

function lpad
{
    len=${#1}
    spaces=$(expr "$2" - "$len")
    for i in $(seq 1 $spaces);do echo -n " "; done
    echo -en $1
    echo -en $3
}

