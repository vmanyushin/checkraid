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

. ./checkraid_vars.sh
. ./checkraid_functions.sh

RAID_SOFTWARE=false
RAID_ADAPTEC=false
RAID_HP=false
RAID_LSI=false
RAID_3WARE=false

install_wget
os_detect
detect_raid_controller

ARCCONF_URL="http://136.243.156.70/files/arcconf_${DIST_ARCH}"

if [[ $RAID_SOFTWARE == true ]]; then
	software_raid_check
elif [[ $RAID_ADAPTEC == true ]]; then
	adaptec_raid_check
fi

echo "done"
cd $OLD_CWD