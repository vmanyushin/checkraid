#!/bin/bash

rm -rf /opt/raid-tools
cd /opt && git clone https://github.com/vmanyushin/raid-tools

rm -rf /opt/raid-tools/.git
rm -rf /opt/raid-tools/packages
rm /opt/raid-tools/.gitignore
rm /opt/raid-tools/build.sh

rm -rf /home/sysop/development/packages/*
fpm -s dir -t deb -v 0.3 -a all -n raid-tools --depends wget --depends gawk --depends pciutils -p /home/sysop/development/packages/ /opt/raid-tools
fpm -s dir -t rpm -v 0.3 -a all -n raid-tools --depends wget --depends gawk --depends pciutils -p /home/sysop/development/packages/ /opt/raid-tools
