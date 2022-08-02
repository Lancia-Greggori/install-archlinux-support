#!/bin/sh

set -eu

[ "$(id -u)" != '0' ] && echo 'Error: this program needs to be run as root' && exit 1

trap 'cp /etc/pacman.conf.orig /etc/pacman.conf;  rm -f repos.html arch-repos.txt universe-repos.txt' INT

# Define some initial variables

NO_MULTILIB='false'

NEWLINE='

'

# Define some useful functions 

print_help()
{

	cat <<EOF
Usage: $0 [OPTIONS]

Available Options:

	--no-multilib	Prevent the multilib repos from being installed in /etc/pacman.conf
EOF

}

add_repos()
{

	# Arg1: the directive to add after
	# Arg2: the file that contains the repos to be added

	# Find the line number that contains the desired directive, and start placing the repos after that

	LINE_NUM="$(( $(grep -Fn "$1" /etc/pacman.conf | cut -d':' -f1) + 1 ))"

	while true; do

		# See if the line does not start with a "Server" or "Include" keyword

		if ! sed -n "${LINE_NUM}p" /etc/pacman.conf | grep -E '^(Include|Server)' 1>/dev/null; then

			sed -i'' "${LINE_NUM}r $2" /etc/pacman.conf

			break

		else

			LINE_NUM="$((LINE_NUM + 1))"

		fi

	done

}

sync_with_repos()
{

	if ! pacman -Sy; then

		echo 'Error: failed to sync using "pacman -Syu"'

		exit 1

	fi

}

[ -n "$*" ] && for arg in "$@"; do

	case "$arg" in

		-h|--help)	print_help && exit 0 ;;

		--no-multilib)	NO_MULTILIB='true' ;;

		*)	echo 'Error: unknown option' && print_help && exit 1 ;;

	esac

done

# Make a backup of /etc/pacman.conf

echo 'Making a copy of /etc/pacman.conf into /etc/pacman.conf.orig...'

cp -i /etc/pacman.conf /etc/pacman.conf.orig

# get the latest universe repos

URL='https://wiki.artixlinux.org/Main/Repositories'

echo 'Getting the latest Universe repos...'

if wget -q "$URL" -O repos.html; then

	awk '/<pre>.*\[universe\]/,/<\/pre>/' repos.html | grep -o '>.\+</a>' \
		| sed -e 's/>//g; s/<\/a>*//g; s/^/Server = /; 1i [universe]' -e "\$a$NEWLINE" > universe-repos.txt

else

	echo "Error: failed to retrieve the list of repositories from $URL"

	exit 1

fi

# Add the universe repos and install artix-archlinux-support pkg

echo 'Adding the Universe repos to /etc/pacman.conf...'

if grep -F '[universe]' /etc/pacman.conf 1>/dev/null; then

	printf '\tThe [universe] directive already exists in /etc/pacman.conf, skipping this step...\n'

else

	add_repos '[galaxy]' 'universe-repos.txt'

fi

sync_with_repos

echo 'Installing artix-archlinux-support...'

if ! pacman -S --noconfirm artix-archlinux-support; then

	echo 'Error: failed to install artix-archlinux-support'

	exit 1

fi

# Add the Arch repos

echo 'Adding Arch repos...'

awk '/^ *\[extra\]/,/<\/pre>/' repos.html | sed -e '/<\/pre>/d; s/^ \+//' -e "\$a$NEWLINE" > arch-repos.txt

# Disable multilib repos if requested

if [ "$NO_MULTILIB" = 'true' ]; then

	LINE_NUM="$(grep -Fn '[multilib]' arch-repos.txt | cut -d':' -f1)"

	while true; do

		if sed -n "${LINE_NUM}p" arch-repos.txt | grep -E '^(Include|Server|\[multilib\])'; then

			sed -i'' "${LINE_NUM}d" arch-repos.txt

		else 

			break

		fi

	done

fi

add_repos '[universe]' 'arch-repos.txt'

echo 'Running "pacman-key --populate archlinux"...'

if ! pacman-key --populate archlinux; then

	echo 'Error: failed in running command "pacman-key --populate archlinux"'

fi

sync_with_repos

rm repos.html universe-repos.txt arch-repos.txt

echo 'Arch repositories have been added successfully, Have a nice day!'

