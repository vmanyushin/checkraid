#!/bin/bash
#
# created: 04.08.2016
# updated: 
# author: vmanyushin@gmail.com
# version: 0.1
# description:
#

if [[ $(whoami) != "root" ]]; then
	echo -e "\nТребуются привилегии пользователя root"
	exit 1
fi

OLD_CWD=$(pwd)
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $CWD


. ./lib/utils.sh
. ./lib/vars.sh
. ./lib/functions.sh

while getopts ":ydh" opt
do
	case $opt in
		y) ANSWER=y    ;; # при запросах y/n отвечаем всегда y
		d) DEBUG=true  ;; # включаем режим отдадки
		h) help_message;; # вывести инструкцию
	esac
done

RAID_SOFTWARE=false
RAID_ADAPTEC=false
RAID_HP=false
RAID_LSI=false
RAID_3WARE=false

os_detect
install_requirements
detect_raid_controller

ARCCONF_URL="http://136.243.156.70/files/$DIST_FAMILY/$DIST_ARCH/arcconf.${DIST_PACKAGE}"
HPUTILS_URL="http://136.243.156.70/files/$DIST_FAMILY/$DIST_ARCH/hputils.${DIST_PACKAGE}"

if [[ $RAID_SOFTWARE == true ]]; then
	software_raid_check
elif [[ $RAID_ADAPTEC == true ]]; then
	adaptec_raid_check
elif [[ $RAID_HP == true ]]; then
	hp_raid_check
fi

echo "done"
cd $OLD_CWD