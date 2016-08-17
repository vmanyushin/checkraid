#!/bin/bash

function help_message
{
	cat <<USAGE
Применение: raid-tools.sh [ОПЦИИ]...

  Скрипт проверяет на наличие в системе RAID массивов и в случае их обнаружения 
  предлагает поставить их на мониторинг

  -y    отвечать всегда Y
  -d    включить отладку
  -h    вывести подсказку

USAGE
	exit 0
}

#==============================================================================
# узнаем под каким дистрибутивом работает скрипт
#
# DIST_FAMILY          - RedHat|Debian
# DIST_NAME            - CentOS|RedHat|Debian|Ubuntu
# DIST_VERSION         - 1.1 идт
# DIST_ARCH            - x86_64|i386
# DIST_PACKAGE         - deb|rpm
# DIST_INSTALL_COMMAND - rpm -i|dpkg -i
#==============================================================================
function os_detect
{
	[[ $DEBUG == true ]] && debug "runnig os_detect()"

	DIST_FAMILY=''
	DIST_NAME=''
	DIST_VERSION=''
	DIST_ARCH=''
	DIST_PACKAGE=''

	[[ -e "/usr/bin/yum" || -e "/bin/rpm" ]] && DIST_FAMILY='RedHat'
	[[ -e "/usr/bin/apt" || -e "/usr/bin/apt-get" || -e "/usr/bin/dpkg" ]] && DIST_FAMILY='Debian'

	[[ $DEBUG == true ]] && debug "DIST_FAMILY  = ${DIST_FAMILY}"

	case "$DIST_FAMILY" in
		"RedHat" )
		if [[ -e /etc/redhat-release ]]; then

			DIST_NAME=$(grep -Po '^(\w+)' /etc/redhat-release)
			DIST_VERSION=$(grep -Po '[0-9]+\.[0-9]+' /etc/redhat-release)
			DIST_PACKAGE="rpm"
			DIST_INSTALL_COMMAND="rpm -i"
		fi
		;;
		"Debian" )
		DIST_PACKAGE="deb"
		DIST_INSTALL_COMMAND="dpkg -i"
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

#==============================================================================
# проверяем на наличие RAID контроллеров в системе
# в случае успеха присваиваем true 
#==============================================================================
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



#==============================================================================
# выводим информацию с поменткой DEBUG и цветом YELLOW
# $1 - строка которую нужно вывести
#==============================================================================
function debug
{
	echo -e "${COLOR_YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]: DEBUG $1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом GREEN
# $1 - строка которую нужно вывести
#==============================================================================
function ok
{
	echo -ne "${COLOR_GREEN}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом RED
# $1 - строка которую нужно вывести
#==============================================================================
function fail
{
	echo -ne "${COLOR_RED}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом YELLOW
# $1 - строка которую нужно вывести
#==============================================================================
function warning
{
	echo -ne "${COLOR_YELLOW}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом CYAN
# $1 - строка которую нужно вывести
#==============================================================================
function notice
{
	echo -ne "${COLOR_CYAN}$1${COLOR_NORMAL}"
}

function install_raid_utils
{
	case "$1" in
	"ARCCONF" )
		filename=/tmp/$(basename ${ARCCONF_URL})
		URL=$ARCCONF_URL
	;;
	"HPUTILS" )
		filename=/tmp/$(basename ${HPUTILS_URL})
		URL=$HPUTILS_URL
	;;
	esac

	echo ""
	echo "Устанавливаю " $(basename $URL)

	wget $URL -O $filename -o /dev/null
	$DIST_INSTALL_COMMAND $filename

	if [[ $? -ne 0 ]]; then
		echo "Не удалось установить пакет ${URL} попробуйте установить его вручную"
		exit 1
	fi

	echo "пакет " $(basename $URL) " установлен"
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

function rpad
{
    len=${#1}
    spaces=$(expr "$2" - "$len")
    echo -en $1
    for i in $(seq 1 $spaces);do echo -n " "; done
    echo -en $3
}

function chr
{
	[ "$1" -lt 256 ] || return 1
	printf "\\$(printf '%03o' "$1")"
}

function ord
{
	LC_CTYPE=C printf '%d' "'$1"
}

function send_notify
{
	local password=$(echo -n "password" | base64 -w 0)
	local subject=$(echo -n "$1" | base64 -w 0)
	local body=$(echo -n "$2" | base64 -w 0)

	wget -q --post-data "password=$password&msgsubject=$subject&msgbody=$body" --header="Content-Type: application/x-www-form-urlencoded" "http://mail.artplanet.su/raid.php"  -O report.html
	wget -q --post-data "password=$password&msgsubject=$subject&msgbody=$body" --header="Content-Type: application/x-www-form-urlencoded" $NOTIFY_URL -O report.html
}