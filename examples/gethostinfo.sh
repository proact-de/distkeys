#! /bin/bash

echo "===== HOST INFORMATION ====="
echo -n "Hostname: " ; hostname

test -f /etc/debian_version && ( echo -n "Debian:   "; cat /etc/debian_version )
test -f /etc/SuSE-release   && ( echo -n "SuSE:     "; cat /etc/SuSE-release )
test -f /etc/redhat-release && ( echo -n "RedHat:   "; cat /etc/redhat-release )

echo -n "Kernel:   " ; uname -a
echo -n "Uptime:   " ; uptime

if [ -f /etc/debian_version ]; then
	echo -e "\nSome installed software:"
	dpkg -l | egrep "( squid|nagios)" | cut -c 1-50
	for software in apache2 dansguardian openvpn postfix squid squid3 nagios2 nagios3; do
		proc=$software

		if test $proc = postfix; then proc=master; fi

		echo "Package information for $software:"
		LANG=C apt-cache policy $software | grep -E '^ ( Installed| Candidate|\*\*\*)'
		echo -n "Running processes: " ; pidof $proc
	done
fi
