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
			nagios2 nagios3 mysql-server mysql-server-4.1 mysql-server-5.0 \
			mysql-server-5.1; do
		procs=$software

		case "$procs" in
			postfix)
				procs=master
				;;
			mysql-server*)
				procs="mysqld_safe mysqld ndbd ndb_mgmd"
				;;
		esac

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

			for proc in $procs; do
				running="$( pidof $proc )"
				if test -n "$running"; then
					echo "    Running '$proc' processes: $running"
				else
					echo "    '$proc' not running."
				fi
			done
		fi
	done
fi
