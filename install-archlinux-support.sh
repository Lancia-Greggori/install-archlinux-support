#!/bin/sh

# version: 1.1.5

# shellcheck disable=SC2064

set -eu


NO_MULTILIB='false'

NEWLINE='

'

PROGRAM_NAME="$(basename "$0")"

ARCH_REPOS_FILE=''; UNIVERSE_REPOS_FILE=''; REPOS_FILE='';

print_help()
{
	cat <<EOF
Usage: $PROGRAM_NAME [OPTIONS]

Available Options:

	--no-multilib	Prevent the multilib repos from being installed in /etc/pacman.conf
EOF
}

print_msg() { echo "$PROGRAM_NAME: $1..." ; }

print_error() { echo "$PROGRAM_NAME: $1" 1>&2 ; }

clean_up()
{
	cp /etc/pacman.conf.orig /etc/pacman.conf

	rm -f "$REPOS_FILE" "$ARCH_REPOS_FILE" "$UNIVERSE_REPOS_FILE"
}

install_pkg()
{
	print_msg "Installing $1"

	if ! pacman -S --noconfirm "$1"; then

		print_error "failed to install $1"

		clean_up

		exit 1

	fi
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

		print_error 'failed to sync using "pacman -Syu"'

		clean_up

		exit 1

	fi
}


[ "$(id -u)" -ne '0' ] && print_error 'this program needs to be run as root' && exit 1

# Ask the user if they really want to proceed

printf 'Warning: this program will install Arch repositories onto your system, are you sure you want to proceed? [y/n] '

read -r ANSWER && [ "$ANSWER" != 'y' ] && exit 1

# Check if Arch repos have already been enabled

if grep -E '^(\[extra\]|\[community\]|\[multilib\])' /etc/pacman.conf 1>/dev/null; then

	print_error 'Arch repos have already been enabled in /etc/pacman.conf'

	exit 1

fi

# Now we start creating the temporary files

ARCH_REPOS_FILE="$(mktemp /tmp/arch-repos-file-XXX)"

UNIVERSE_REPOS_FILE="$(mktemp /tmp/universe-repos-file-XXX)"

REPOS_FILE="$(mktemp /tmp/repos-file-XXX)"

trap "cp /etc/pacman.conf.orig /etc/pacman.conf;  rm -f $REPOS_FILE $ARCH_REPOS_FILE $UNIVERSE_REPOS_FILE" INT


[ -n "$*" ] && for arg in "$@"; do

	case "$arg" in

		-h|--help)	print_help && exit 0 ;;

		--no-multilib)	NO_MULTILIB='true' ;;

		*)	print_error 'unknown option' && print_help && exit 1 ;;

	esac

done

# Make a backup of /etc/pacman.conf

print_msg 'Making a backup copy of /etc/pacman.conf into /etc/pacman.conf.orig '

cp -i /etc/pacman.conf /etc/pacman.conf.orig

# Install wget if not installed

if ! command -v wget 1>/dev/null 2>&1; then

	install_pkg wget

fi

# get the latest universe repos

URL='https://wiki.artixlinux.org/Main/Repositories'

print_msg 'Getting the latest Universe repos'

if wget -q "$URL" -O "$REPOS_FILE"; then

	awk '/<pre>.*\[universe\]/,/<\/pre>/' "$REPOS_FILE" | grep -o '>.\+</a>' \
		| sed -e 's/>//g; s/<\/a>*//g; s/^/Server = /; 1i [universe]' -e "\$a$NEWLINE" > "$UNIVERSE_REPOS_FILE"

else

	print_error "failed to retrieve the list of repositories from $URL"

	exit 1

fi

# Add the universe repos and install artix-archlinux-support pkg

print_msg 'Adding the Universe repos to /etc/pacman.conf'

if grep -F '[universe]' /etc/pacman.conf 1>/dev/null; then

	print_msg 'The [universe] directive already exists in /etc/pacman.conf, skipping this step'

else

	add_repos '[galaxy]' "$UNIVERSE_REPOS_FILE"

fi

sync_with_repos

install_pkg artix-archlinux-support

# Add the Arch repos

print_msg 'Adding Arch repos'

awk '/^ *\[extra\]/,/<\/pre>/' "$REPOS_FILE" | sed -e '/<\/pre>/d; s/^ \+//' -e "\$a$NEWLINE" > "$ARCH_REPOS_FILE"

# Disable multilib repos if requested

if [ "$NO_MULTILIB" = 'true' ]; then

	LINE_NUM_START="$(grep -Fn '[multilib]' "$ARCH_REPOS_FILE" | cut -d':' -f1)"

	LINE_NUM_END="$LINE_NUM_START"

	while true; do

		if sed -n "$((LINE_NUM_END + 1))p" "$ARCH_REPOS_FILE" | grep -E '^(Include|Server)'; then

			LINE_NUM_END="$((LINE_NUM_END + 1))"

		else

			break

		fi

	done

	sed -i'' "${LINE_NUM_START},${LINE_NUM_END}d" "$ARCH_REPOS_FILE"

fi

add_repos '[universe]' "$ARCH_REPOS_FILE"

print_msg 'Running "pacman-key --populate archlinux"'

if ! pacman-key --populate archlinux; then

	print_error 'failed in running command "pacman-key --populate archlinux"'

fi

sync_with_repos

rm "$REPOS_FILE" "$UNIVERSE_REPOS_FILE" "$ARCH_REPOS_FILE"

echo 'Arch repositories have been added successfully, Have a nice day!'
