#!/usr/local/bin/bash

# Copyright (C) 2012 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
# This file is licensed under the GPLv2+. Please see COPYING for more information.

umask 077

PREFIX="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
ID="$PREFIX/.gpg-id"
GPG_OPTS="--quiet --yes --batch"

version() {
	cat <<_EOF
|-----------------------|
|   Password Store      |
|         v.1.4         |
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
    $program init [--reencrypt,-e] gpg-id
        Initialize new password storage and use gpg-id for encryption.
        Optionally reencrypt existing passwords using new gpg-id.
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
    $program generate [--no-symbols,-n] [--force,-f] pass-name pass-length
        Generate a new password of pass-length with optionally no symbols.
        Prompt before overwriting existing password unless forced.
    $program rm [--recursive,-r] [--force,-f] pass-name
        Remove existing password or directory, optionally forcefully.
    $program help
        Show this text.
    $program version
        Show version information.

More information may be found in the pass(1) man page.
_EOF
}
is_command() {
	case "$1" in
		init|ls|list|show|insert|edit|generate|remove|rm|delete|help|--help|version|--version) return 0 ;;
		*) return 1 ;;
	esac
}
yesno() {
	read -p "$1 [y/N] " response
	[[ $response == "y" || $response == "Y" ]] || exit 1
}
#
# BEGIN Platform definable
#

tmpdir() {
	ramdisk="/var/tmp/password-store.ramdisk"
	if [[ -d $ramdisk && -w $ramdisk && -x $ramdisk ]]; then
		tmp_dir="$(TMPDIR=$ramdisk mktemp -t "$template" -d)"
	else
		yesno "$(echo    "A ramdisk does not exist at $ramdisk, which means that it may"
			 echo    "be difficult to entirely erase the temporary non-encrypted"
			 echo    "password file after editing. Are you sure you would like to"
			 echo -n "continue?")"

		tmp_dir="$(mktemp -t "$template" -d)"
	fi
}

GPG="gpg2"
GETOPT="/usr/local/bin/getopt"

#
# END Platform definable
#

program="$(basename "$0")"
command="$1"
if is_command "$command"; then
	shift
else
	command="show"
fi

case "$command" in
	init)
		reencrypt=0

		opts="$($GETOPT -o e -l reencrypt -n "$program" -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-e|--reencrypt) reencrypt=1; shift ;;
			--) shift; break ;;
		esac done

		if [[ $# -ne 1 ]]; then
			echo "Usage: $program $command [--reencrypt,-e] gpg-id"
			exit 1
		fi

		gpg_id="$1"
		mkdir -v -p "$PREFIX"
		echo "$gpg_id" > "$ID"
		echo "Password store initialized for $gpg_id."

		if [[ $reencrypt -eq 1 ]]; then
			find "$PREFIX" -iname '*.gpg' | while read passfile; do
				$GPG -d $GPG_OPTS "$passfile" | $GPG -e -r "$gpg_id" -o "$passfile.new" $GPG_OPTS &&
				mv -v "$passfile.new" "$passfile"
			done
		fi
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

if [[ -n $PASSWORD_STORE_KEY ]]; then
	ID="$PASSWORD_STORE_KEY"
elif [[ ! -f $ID ]]; then
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
		if [[ $err -ne 0 ]]; then
			echo "Usage: $program $command [pass-name]"
			exit 1
		fi

		path="$1"
		if [[ -d $PREFIX/$path ]]; then
			if [[ -z $path ]]; then
				echo "Password Store"
			else
				echo $path
			fi
			tree --noreport "$PREFIX/$path" | tail -n +2 | sed 's/\(.*\)\.gpg$/\1/'
		else
			passfile="$PREFIX/$path.gpg"
			if [[ ! -f $passfile ]]; then
				echo "$path is not in the password store."
				exit 1
			fi
			exec $GPG -d $GPG_OPTS "$passfile"
		fi
		;;
	insert)
		multiline=0
		noecho=0
		force=0

		opts="$($GETOPT -o mnf -l multiline,no-echo,force -n "$program" -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-m|--multiline) multiline=1; shift ;;
			-n|--no-echo) noecho=1; shift ;;
			-f|--force) force=1; shift ;;
			--) shift; break ;;
		esac done

		if [[ $err -ne 0 || ( $multiline -eq 1 && $noecho -eq 1 ) || $# -ne 1 ]]; then
			echo "Usage: $program $command [--no-echo,-n | --multiline,-m] [--force,-f] pass-name"
			exit 1
		fi
		path="$1"
		passfile="$PREFIX/$path.gpg"

		[[ $force -eq 0 && -e $passfile ]] && yesno "An entry already exists for $path. Overwrite it?"

		mkdir -p -v "$PREFIX/$(dirname "$path")"

		if [[ $multiline -eq 1 ]]; then
			echo "Enter contents of $path and press Ctrl+D when finished:"
			echo
			$GPG -e -r "$ID" -o "$passfile" $GPG_OPTS
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

		tmpdir #Defines $tmp_dir
		tmp_file="$(TMPDIR="$tmp_dir" mktemp -t "$template")"

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
		;;
	generate)
		force=0
		symbols="-y"

		opts="$($GETOPT -o ncf -l no-symbols,force -n "$program" -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-n|--no-symbols) symbols=""; shift ;;
			-f|--force) force=1; shift ;;
			--) shift; break ;;
		esac done

		if [[ $err -ne 0 || $# -ne 2 ]]; then
			echo "Usage: $program $command [--no-symbols,-n] [--force,-f] pass-name pass-length"
			exit 1
		fi
		path="$1"
		length="$2"
		if [[ ! $length =~ ^[0-9]+$ ]]; then
			echo "pass-length \"$length\" must be a number."
			exit 1
		fi
		mkdir -p -v "$PREFIX/$(dirname "$path")"
		passfile="$PREFIX/$path.gpg"

		[[ $force -eq 0 && -e $passfile ]] && yesno "An entry already exists for $path. Overwrite it?"

		pass="$(pwgen -s $symbols $length 1)"
		[[ -n $pass ]] || exit 1
		$GPG -e -r "$ID" -o "$passfile" $GPG_OPTS <<<"$pass"
		
		echo "The generated password to $path is:"
		echo "$pass"
		;;
	delete|rm|remove)
		recursive=""
		force=0

		opts="$($GETOPT -o rf -l recursive,force -n "$program" -- "$@")"
		err=$?
		eval set -- "$opts"
		while true; do case $1 in
			-r|--recursive) recursive="-r"; shift ;;
			-f|--force) force=1; shift ;;
			--) shift; break ;;
		esac done
		if [[ $# -ne 1 ]]; then
			echo "Usage: $program $command [--recursive,-r] [--force,-f] pass-name"
			exit 1
		fi
		path="$1"

		passfile="$PREFIX/${path%/}"
		if [[ ! -d $passfile ]]; then
			passfile="$PREFIX/$path.gpg"
			if [[ ! -f $passfile ]]; then
				echo "$path is not in the password store."
				exit 1
			fi
		fi

		[[ $force -eq 1 ]] || yesno "Are you sure you would like to delete $path?"

		rm $recursive -f -v "$passfile"
		;;
	*)
		usage
		exit 1
		;;
esac
exit 0
