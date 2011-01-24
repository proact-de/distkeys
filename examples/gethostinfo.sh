#!/bin/sh

test -f /etc/debian_version && ( echo -n "Debian: "; cat /etc/debian_version )
test -f /etc/SuSE-release   && ( echo -n "SuSE:   "; cat /etc/SuSE-release )
echo -n "Kernel: " ; uname -a
