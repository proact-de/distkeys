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
	for software in apache2 dansguardian openvpn postfix squid squid3 nagios2 nagios3; do
		proc=$software

		if test $proc = postfix; then proc=master; fi

		OUT=$( LANG=C apt-cache policy $software )

		if ! (echo "$OUT" | grep -q "Installed.*none" ) ; then
			echo "Package information for $software:"
			echo "$OUT" | grep -E '^ ( Installed| Candidate|\*\*\*)' 2> /dev/null
			if pidof $proc >/dev/null; then
				echo -n "Running processes: " ; pidof $proc
			else
				echo "Not running."
			fi
		fi
	done
fi
