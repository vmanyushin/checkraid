#!/bin/bash

rm -rf /opt/raid-tools
cd /opt && git clone https://github.com/vmanyushin/raid-tools

rm -rf /opt/raid-tools/.git
rm /opt/raid-tools/.gitignore

rm -rf /home/sysop/development/packages/*
fpm -s dir -t deb -v 0.3 -a all -n raid-tools -p /home/sysop/development/packages/ /opt/raid-tools
fpm -s dir -t rpm -v 0.3 -a all -n raid-tools -p /home/sysop/development/packages/ /opt/raid-tools
