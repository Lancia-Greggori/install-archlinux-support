#!/bin/sh

set -eux

NEWLINE='
'

wget 'https://wiki.artixlinux.org/Main/Repositories' -O repos.html

awk '/<pre> *\[universe\]/,/<\/pre>/' repos.html | grep -o '>.\+</a>' | sed -e 's/>//g; s/<\/a>*//g; s/^/Server = /; 1i [universe]' -e "\$a$NEWLINE" >universe-repos.txt

GALAXY_DIRECTIVE_LINE_NUMBER="$(grep -Fn '[galaxy]' /etc/pacman.conf | cut -d':' -f1)"

LINE_NUM="$((GALAXY_DIRECTIVE_LINE_NUMBER + 1))"


# using the GALAXY_DIRECTIVE_LINE_NUMBER variable defined above, start at the next line number (LINE_NUM) after the "[galaxy]" directive 

printf 'Adding Universe repos to /etc/pacman.conf...'

if grep -F '[universe]' /etc/pacman.conf 1>/dev/null; then

	printf '\tthe [universe] directive already exists in /etc/pacman.conf, skipping this step...\n'

else

	while true; do
	
		# See if the line does not start with a "Server" or "Include" keyword
	
		if ! sed -n "${LINE_NUM}p" /etc/pacman.conf | grep -E '^(Include|Server)'; then
	
			sed -i'' "${LINE_NUM}r universe-repos.txt" /etc/pacman.conf

			break
	
		else
	
			LINE_NUM="$((LINE_NUM + 1))"
	
		fi
	
	done

fi


if ! pacman -Sy; then

	echo 'Error: failed to sync using "pacman -Syu"'

	exit 1

fi

if ! pacman -S artix-archlinux-support; then

	echo 'Error: failed to install artix-archlinux-support'

	exit 1

fi
