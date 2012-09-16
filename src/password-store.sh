#!/usr/local/bin/bash

# (C) Copyright 2012 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
# This is released under the GPLv2+. Please see COPYING for more information.

umask 077

PREFIX="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
ID="$PREFIX/.gpg-id"
GITDIR="$PREFIX/.git"
GPG_OPTS="--quiet --yes --batch"
GETOPT=/usr/local/bin/getopt
GPG=gpg2
GIT=git

export GIT_DIR="$GITDIR"
export GIT_WORK_TREE="$PREFIX"

version() {
	cat <<_EOF
|-----------------------|
|   Password Store      |
|       v.1.3.1         |
|       by zx2c4        |
|                       |
|    Jason@zx2c4.com    |
|  Jason A. Donenfeld   |
|-----------------------|
_EOF
}
usage() {
	version
	cat <<_EOF

Usage:
    $program init gpg-id
        Initialize new password storage and use gpg-id for encryption.
    $program [ls] [subfolder]
        List passwords.
    $program [show] pass-name
        Show existing password
    $program insert [--no-echo,-n | --multiline,-m] [--force,-f] pass-name
        Insert new password. Optionally, the console can be enabled to not
        echo the password back. Or, optionally, it may be multiline. Prompt
        before overwriting existing password unless forced.
    $program edit pass-name
        Insert a new password or edit an existing password using ${EDITOR:-vi}.
    $program generate [--no-symbols,-n] pass-name pass-length
        Generate a new password of pass-length with optionally no symbols.
    $program rm pass-name
        Remove existing password.
    $program push
        If the password store is a git repository, push the latest changes.
    $program pull
        If the password store is a git repository, pull the latest changes.
    $program git git-command-args...
        If the password store is a git repository, execute a git command
        specified by git-command-args.
    $program help
        Show this text.
    $program version
        Show version information.
_EOF
}
isCommand() {
	case "$1" in
		init|ls|list|show|insert|edit|generate|remove|rm|delete|push|pull|git|help|--help|version|--version) return 0 ;;
		*) return 1 ;;
	esac
}
program="$(basename "$0")"
command="$1"
if isCommand "$command"; then
	shift
else
	command="show"
fi

case "$command" in
	init)
		if [[ $# -ne 1 ]]; then
			echo "Usage: $program $command gpg-id"
			exit 1
		fi
		gpg_id="$1"
		mkdir -v -p "$PREFIX"
		echo "$gpg_id" > "$ID"
		echo "Password store initialized for $gpg_id."
		exit 0
		;;
	help|--help)
		usage
		exit 0
		;;
	version|--version)
		version
		exit 0
		;;
esac

if ! [[ -f $ID ]]; then
	echo "You must run:"
	echo "    $program init your-gpg-id"
	echo "before you may use the password store."
	echo
	usage
	exit 1
else
	ID="$(head -n 1 "$ID")"
fi

case "$command" in
	show|ls|list)
		err=$?

		if [[ $err -ne 0 ]]; then
			echo "Usage: $program $command [pass-name]"
			exit 1
		fi

		path="$1"
		if [[ -d $PREFIX/$path ]]; then
			if [[ $path == "" ]]; then
				echo "Password Store"
			else
				echo $path
			fi
			tree --noreport "$PREFIX/$path" | tail -n +2 | sed 's/\(.*\)\.gpg$/\1/'
		else
			passfile="$PREFIX/$path.gpg"
			if ! [[ -f $passfile ]]; then
				echo "$path is not in the password store."
				exit 1
			fi
		    exec $GPG -q -d --yes --batch "$passfile"
		fi
		;;
	insert)
		ml=0
		noecho=0
		force=0

		opts="$($GETOPT -o mnf -l multiline,no-echo,force -n $program -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-m|--multiline) ml=1; shift ;;
			-n|--no-echo) noecho=1; shift ;;
			-f|--force) force=1; shift ;;
			--) shift; break ;;
		esac done

		if [[ $err -ne 0 || ( $ml -eq 1 && $noecho -eq 1 ) || $# -ne 1 ]]; then
			echo "Usage: $program $command [--no-echo,-n | --multiline,-m] [--force,-f] pass-name"
			exit 1
		fi
		path="$1"
		passfile="$PREFIX/$path.gpg"

		if [[ $force -eq 0 && -e $passfile ]]; then
			prompt="An entry already exists for $path. Overwrite it [y/N]? "
			read -p "$prompt" yesno
			[[ $yesno == "y" || $yesno == "Y" ]] || exit 1
		fi

		mkdir -p -v "$PREFIX/$(dirname "$path")"

		if [[ $ml -eq 1 ]]; then
			echo "Enter contents of $path and press Ctrl+D when finished:"
			echo
			cat | $GPG -e -r "$ID" -o "$passfile" $GPG_OPTS
		elif [[ $noecho -eq 1 ]]; then
			while true; do
				read -p "Enter password for $path: " -s password
				echo
				read -p "Retype password for $path: " -s password_again
				echo
				if [[ $password == $password_again ]]; then
					$GPG -e -r "$ID" -o "$passfile" $GPG_OPTS <<<"$password"
					break
				else
					echo "Error: the entered passwords do not match."
				fi
			done
		else
			read -p "Enter password for $path: " -e password
			$GPG -e -r "$ID" -o "$passfile" $GPG_OPTS <<<"$password"
		fi
		if [[ -d $GITDIR ]]; then
			$GIT add "$passfile"
			$GIT commit -m "Added given password for $path to store."
		fi
		;;
	edit)
		if [[ $# -ne 1 ]]; then
			echo "Usage: $program $command pass-name"
			exit 1
		fi

		path="$1"
		mkdir -p -v "$PREFIX/$(dirname "$path")"
		passfile="$PREFIX/$path.gpg"
		template="$program.XXXXXXXXXXXXX"

		trap 'rm -rf "$tmp_dir" "$tmp_file"' INT TERM EXIT

		if [[ -d /dev/shm && -w /dev/shm && -x /dev/shm ]]; then
			tmp_dir="$(TMPDIR=/dev/shm mktemp -t $template -d)"
		else
			prompt=$(echo    "Your system does not have /dev/shm, which means that it may"
			         echo    "be difficult to entirely erase the temporary non-encrypted"
			         echo    "password file after editing. Are you sure you would like to"
			         echo -n "continue? [y/N] ")
			read -p "$prompt" yesno
			[[ $yesno == "y" || $yesno == "Y" ]] || exit 1
			tmp_dir="$(mktemp -t $template -d)"
		fi
		tmp_file="$(TMPDIR="$tmp_dir" mktemp -t $template)"

		action="Added"
		if [[ -f $passfile ]]; then
			$GPG -d -o "$tmp_file" $GPG_OPTS "$passfile" || exit 1
			action="Edited"
		fi
		${EDITOR:-vi} "$tmp_file"
		while ! $GPG -e -r "$ID" -o "$passfile" $GPG_OPTS "$tmp_file"; do
			echo "GPG encryption failed. Retrying."
			sleep 1
		done

		if [[ -d $GITDIR ]]; then
			$GIT add "$passfile"
			$GIT commit -m "$action password for $path using ${EDITOR:-vi}."
		fi
		;;
	generate)
		symbols="-y"

		opts="$($GETOPT -o nc -l no-symbols -n $program -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-n|--no-symbols) symbols=""; shift ;;
			--) shift; break ;;
		esac done

		if [[ $err -ne 0 || $# -ne 2 ]]; then
			echo "Usage: $program $command [--no-symbols,-n] pass-name pass-length"
			exit 1
		fi
		path="$1"
		length="$2"
		if ! [[ $length =~ ^[0-9]+$ ]]; then
			echo "pass-length \"$length\" must be a number."
			exit 1
		fi
		mkdir -p -v "$PREFIX/$(dirname "$path")"
		pass="$(pwgen -s $symbols $length 1)"
		passfile="$PREFIX/$path.gpg"
		$GPG -e -r "$ID" -o "$passfile" $GPG_OPTS <<<"$pass"
		if [[ -d $GITDIR ]]; then
			$GIT add "$passfile"
			$GIT commit -m "Added generated password for $path to store."
		fi
		echo "The generated password to $path is:"
		echo "$pass"
		;;
	delete|rm|remove)
		if [[ $# -ne 1 ]]; then
			echo "Usage: $program $command pass-name"
			exit
		fi
		path="$1"
		passfile="$PREFIX/$path.gpg"
		if ! [[ -f $passfile ]]; then
			echo "$path is not in the password store."
			exit 1
		fi
		rm -i -v "$passfile"
		if [[ -d $GITDIR ]] && ! [[ -f $passfile ]]; then
			$GIT rm -f "$passfile"
			$GIT commit -m "Removed $path from store."
		fi
		;;
	push|pull)
		if [[ -d $GITDIR ]]; then
			exec $GIT $command "$@"
		else
			echo "Error: the password store is not a git repository."
			exit 1
		fi
		;;
	git)
		if [[ $1 == "init" ]]; then
			username=$2
			useremail=$3

			$GIT init

			if [ -z "$username" ]; then
			    current=$($GIT config user.name)
			    prompt="Set your git user.name: "
			    read -e -i "$current" -p "$prompt" username
                username="${username:-$username}"
			fi
			if [ -z "$useremail" ]; then
			    current=$($GIT config user.email)
			    prompt="Set your git user.email: "
			    read -e -i "$current" -p "$prompt" useremail
                useremail="${useremail:-$useremail}"
			fi
			$GIT config user.name "$username"
			$GIT config user.email "$useremail"
			echo .gpg-id > $PREFIX/.gitignore
			$GIT add .
			$GIT commit -m "Adding existing passwords to the store."
		elif [[ -d $GITDIR ]]; then
			exec $GIT "$@"
		else
			echo "Error: the password store is not a git repository."
			exit 1
		fi
		;;
	*)
		usage
		exit 1
		;;
esac
exit 0
