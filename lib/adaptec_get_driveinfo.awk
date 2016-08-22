#!/bin/gawk
#
# created: 21.08.2016
# updated: 
# author: vmanyushin@gmail.com
# version: 0.1
# description: 
#
function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
function trim(s)  { return rtrim(ltrim(s)); }

BEGIN {
    m = 0
    state   = ""
    model   = ""
    size    = ""
    serial  = ""
    wrcache = ""
    con_no  = ""
    dev_no  = ""
}

{
    if(/\W+[-]+$/ && m == 1) {
        m=0
        if(con == con_no && dev == dev_no) {
            print con_no "," dev_no "," model "," serial "," size "," state
            exit
        }
    }

    if(m == 1) {
        split($0, a, ": ")
        key = trim(a[1])

        if (key == "State") {
            state = a[2]
        }

        if (key == "Model") {
            model = a[2]
        }

        if (key == "Total Size") {
            size = a[2]
        }

        if (key == "Serial number" ) {
            serial = a[2]
        }

        if (key == "Write Cache" ) {
            wrcache = a[2]
        }

        if (key == "Reported Location" ) {
            match(a[2], /Connector ([0-9]+), Device ([0-9]+)/, l)
            con_no=l[1];dev_no=l[2]
        }
    }

    if(/Device #[0-9]+/) {
        m=1
    }
}
