#! /bin/bash

echo "===== HOST INFORMATION ====="
echo -n "Hostname: "
# 'echo $( ... )' translates newlines into spaces
echo $( hostname -f; echo '--'; hostname -A; echo "("; hostname -I; echo ")" )

test -f /etc/debian_version \
	&& ( echo -n "Debian:   "; cat /etc/debian_version )
test -f /etc/SuSE-release   \
	&& ( echo -n "SuSE:     "; cat /etc/SuSE-release )
test -f /etc/redhat-release \
	&& ( echo -n "RedHat:   "; cat /etc/redhat-release )

echo -n "Kernel:   " ; uname -a
echo -n "Uptime:   " ; uptime

if [ -f /etc/debian_version ]; then
	echo -e "\nSome installed software:"
	for software in apache2 dansguardian openvpn postfix squid squid3 \
			nagios2 nagios3; do
		proc=$software

		if test $proc = postfix; then proc=master; fi

		policy="$( apt-cache policy $software 2> /dev/null )"
		installed="$( echo "$policy" \
			| grep -E '^  Installed:' | awk '{ print $2 }' )"
		candidate="$( echo "$policy" \
			| grep -E '^  Candidate:' | awk '{ print $2 }' )"

		if test -n "$installed" -a "$installed" != '(none)'; then
			echo "  Package information for $software:"
			echo "    Installed: $installed"

			if test -n "$candidate" \
				&& dpkg --compare-versions "$installed" lt "$candidate";
			then
				echo "    Not up to date (candidate: $candidate)!"
			fi

			running="$( pidof $proc )"
			if test -n "$running"; then
				echo "    Running processes: $running"
			else
				echo "    Not running."
			fi
		fi
	done
fi
