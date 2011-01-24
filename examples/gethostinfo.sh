#!/bin/sh

echo "===== HOST INFORMATION ====="
echo -n "Hostname: " ; hostname

test -f /etc/debian_version && ( echo -n "Debian:   "; cat /etc/debian_version )
test -f /etc/SuSE-release   && ( echo -n "SuSE:     "; cat /etc/SuSE-release )
test -f /etc/redhat-release && ( echo -n "RedHat:   "; cat /etc/redhat-release )

echo -n "Kernel:   " ; uname -a

if [ -f /etc/debian_version ]; then
	echo -e "\nSome installed software:"
	COLUMNS=80 dpkg -l | egrep "( apache2 | dansguardian | openvpn | postfix | squid|nagios)" | cut -c 1-30
fi
