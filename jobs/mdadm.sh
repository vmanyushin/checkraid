#!/bin/bash

. ./checkraid_vars.sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cat /proc/mdstat > $VARDIR/softraid/current_state

STATE1=$(md5sum $VARDIR/softraid/initial_state | cut -d" " -f1 )
STATE2=$(md5sum $VARDIR/softraid/current_state | cut -d" " -f1 )

if [[ "$STATE1" != "$STATE2" ]]; then
    logger -t softraid-mon "состояние RAID массива или одного из дисков изменился"
else
    logger -t softraid-mon "состояние RAID массивов оптимальное"
fi
