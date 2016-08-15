#!/bin/bash

local line CONTROLLER_SLOT

for line in $(hpacucli ctrl all show detail)
do
	[[ $line =~ 'Slot:' ]] && CONTROLLER_SLOT="${line#[[:space:]]*Slot:[[:space:]]}"
done

$(hpacucli ctrl slot=$CONTROLLER_SLOT show status | grep -v "^$" | sed -re "s/\s{2,}//" > $VARDIR/HP/current_state)
$(hpacucli ctrl slot=$CONTROLLER_SLOT ld all show status | grep -v "^$" | sed -re "s/\s{2,}//" >> $VARDIR/HP/current_state)

STATE1=$(md5sum $VARDIR/HP/initial_state | cut -d" " -f1 )
STATE2=$(md5sum $VARDIR/HP/current_state | cut -d" " -f1 )

if [[ "$STATE1" != "$STATE2" ]]; then
    logger -t hp_smartarray-mon "состояние RAID массива или одного из дисков изменилось"
else
    logger -t hp_smartarray-mon "состояние RAID массивов оптимальное"
fi
