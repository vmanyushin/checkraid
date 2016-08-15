#!/bin/bash

DEBUG=true

VARDIR=/var/lib/raid_status
mkdir -p $VARDIR/{softraid,adaptec,3ware,HP,LSI}

SOFTRAID_INIT_STATE=$VARDIR/softraid/initial_state
ADAPTEC_INIT_STATE=$VARDIR/adaptec/initial_state
HP_INIT_STATE=$VARDIR/HP/initial_state

# text color
COLOR_NORMAL='\e[0m'        #  ${WHITE}
COLOR_BLACK='\033[0;30m'    #  ${BLACK}
COLOR_RED='\033[0;31m'      #  ${RED}
COLOR_GREEN='\033[0;32m'    #  ${GREEN}
COLOR_YELLOW='\033[0;33m'   #  ${YELLOW}
COLOR_BLUE='\033[0;34m'     #  ${BLUE}
COLOR_MAGENTA='\033[0;35m'  #  ${MAGENTA}
COLOR_CYAN='\033[0;36m'     #  ${CYAN}
COLOR_GRAY='\033[0;37m'     #  ${GRAY}
