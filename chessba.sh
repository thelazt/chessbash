#!/usr/bin/env bash
#
# Chess Bash
# a simple chess game written in an inappropriate language :)
#
# Copyright (c) 2015 by Bernhard Heinloth <bernhard@heinloth.net>
# Copyright (c) 2021 by Igor Le Masson
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


# Bash version test
if ((BASH_VERSINFO[0] < 4)); then
	echo "Sorry, it is required at least bash-4.0 to run $0." >&2
	exit 1
fi

# Default values
strength=3
namePlayerA="Player"
namePlayerB="AI"
color=true
colorPlayerA=4
colorPlayerB=1
colorHover=4
colorHelper=true
colorFill=true
ascii=false
warnings=false
computer=-1
mouse=true
guiconfig=false
cursor=true
sleep=2
cache=""
cachecompress=false
unicodelabels=true
port=12433

# internal values
timestamp=$( date +%s%N )
fifopipeprefix="/tmp/chessbashpipe"
selectedX=-1
selectedY=-1
selectedNewX=-1
selectedNewY=-1
remote=0
remoteip=127.0.0.1
remotedelay=0.1
remotekeyword="remote"
aikeyword="ai"
aiPlayerA="Marvin"
aiPlayerB="R2D2"
A=-1
B=1
originY=4
originX=7
hoverX=0
hoverY=0
hoverInit=false
labelX=-2
labelY=9
type stty >/dev/null 2>&1 && useStty=true || useStty=false

# version build number
build="0.41"

# Choose unused color for hover
while (( colorHover == colorPlayerA || colorHover == colorPlayerB )) ; do
	(( colorHover++ ))
done

# Check Unicode availbility
# We do this using a trick: printing a special zero-length unicode char (http://en.wikipedia.org/wiki/Combining_Grapheme_Joiner) and retrieving the cursor position afterwards.
# If the cursor position is at beginning, the terminal knows unicode. Otherwise it has printed some replacement character.
echo -en "\e7\e[s\e[H\r\xcd\x8f\e[6n" && read -r -sN6 -t0.1 x
if [[ "${x:4:1}" == "1" ]] ; then
	ascii=false
	unicodelabels=true
else
	ascii=true
	unicodelabels=false
fi
echo -e "\e[u\e8\e[2K\r\e[0m\nWelcome to \e[1mChessBa.sh\e[0m - a Chess game written in Bash \e[2mby Bernhard Heinloth, 2015\e[0m\n"

# Print version information
function version() {
	echo ChessBash $build
}

# Wait for key press
# no params/return
function anyKey(){
	$useStty && stty echo
	echo -e "\e[2m(Press any key to continue)\e[0m"
	read -r -sN1
	$useStty && stty -echo
}

# Error message, p.a. on bugs
# Params:
#	$1	message
# (no return value, exit game)
function error() {
	if $color ; then
		echo -e "\e[0;1;41m $1 \e[0m\n\e[3m(Script exit)\e[0m" >&2
	else
		echo -e "\e[0;1;7m $1 \e[0m\n\e[3m(Script exit)\e[0m" >&2
	fi
	anyKey
	exit 1
}

# Check prerequisits (additional executables)
# taken from an old script of mine (undertaker-tailor)
# Params:
#	$1	name of executable
function require() {
	type "$1" >/dev/null 2>&1 ||
		{
			echo "This requires $1 but it is not available on your system. Aborting." >&2
			exit 1
		}
}

# Validate a number string
# Params:
#	$1	String with number
# Return 0 if valid, 1 otherwise
function validNumber() {
	if [[ "$1" =~ ^[0-9]+$ ]] ; then
		return 0
	else
		return 1
	fi
}

# Validate a port string
# Must be non privileged (>1023)
# Params:
#	$1	String with port number
# Return 0 if valid, 1 otherwise
function validPort() {
	if validNumber "$1" && (( 1 < 65536 && 1 > 1023 )) ; then
		return 0
	else
		return 1
	fi
}

# Validate an IP v4 or v6 address
# source: http://stackoverflow.com/a/9221063
# Params:
#	$1	IP address to validate
# Return 0 if valid, 1 otherwise
function validIP() {
	if [[ "$1" =~ ^(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))|((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))))$ ]] ; then
		return 0
	else
		return 1
	fi
}

# Named ANSI colors
declare -a colors=( "black" "red" "green" "yellow" "blue" "magenta" "cyan" "white" )

# Retrieve ANSI color code from string
# Black and white are ignored!
# Params:
#	$1	Color string
# Return Color code or 0 if not a valid
function getColor() {
	local c
	for (( c=1; c<7; c++ )) ; do
		local v=${colors[$c]:0:1}
		local i=${1:0:1}
		if [[ "${v^^}" == "${i^^}" || "$c" -eq "$i" ]] ; then
			return "$c"
		fi
	done
	return 0
}

# Check if ai player
# Params:
#	$1	player
# Return status code 0 if ai player
function isAI() {
	if (( $1 < 0 )) ; then
		if [[ "${namePlayerA,,}" == "${aikeyword,,}" ]] ; then
			return 0
		else
			return 1
		fi
	else
		if [[ "${namePlayerB,,}" == "${aikeyword,,}" ]] ; then
			return 0
		else
			return 1
		fi
	fi
}

# Help message
# Writes text to stdout
function help {
	echo
	echo -e "\e[1mChess Bash\e[0m - a small chess game written in Bash"
	echo
	echo -e "\e[4mUsage:\e[0m $0 [options]"
	echo
	echo -e "\e[4mConfiguration options\e[0m"
	echo "    -g         Use a graphical user interface (instead of more parameters)"
	echo
	echo -e "\e[4mGame options\e[0m"
	echo -e "    -a \e[2mNAME\e[0m    Name of first player, \"$aikeyword\" for computer controlled or the"
	echo "               IP address of remote player (Default: $namePlayerA)"
	echo -e "    -b \e[2mNAME\e[0m    Name of second player, \"$aikeyword\" for computer controlled or"
	echo -e "               \"$remotekeyword\" for another player (Default: \e[2m$namePlayerB\e[0m)"
	echo -e "    -s \e[2mNUMBER\e[0m  Strength of computer (Default: \e[2m$strength\e[0m)"
	echo -e "    -w \e[2mNUMBER\e[0m  Waiting time for messages in seconds (Default: \e[2m$sleep\e[0m)"
	echo
	echo -e "\e[4mNetwork settings for remote gaming\e[0m"
	echo -e "    -P \e[2mNUMBER\e[0m  Set port for network connection (Default: \e[2m$port\e[0m)"
	echo -e "\e[1;33mAttention:\e[0;33m On a network game the person controlling the first player / A"
	echo -e "(using \"\e[2;33m-b $remotekeyword\e[0;33m\" as parameter) must start the game first!\e[0m"
	echo
	echo -e "\e[4mCache management\e[0m"
	echo -e "    -c \e[2mFILE\e[0m    Makes cache permanent - load and store calculated moves"
	echo "    -z         Compress cache file (only to be used with -c, requires gzip)"
	echo -e "    -t \e[2mSTEPS\e[0m   Exit after STEPS ai turns and print time (for benchmark)"
	echo
	echo -e "\e[4mOutput control\e[0m"
	echo "    -h         This help message"
	echo "    -v         Version information"
	echo "    -V         Disable VT100 cursor movement (for partial output changes)"
	echo "    -M         Disable terminal mouse support"
	echo "    -i         Enable verbose input warning messages"
	echo "    -l         Board labels in ASCII (instead of Unicode)"
	echo "    -p         Plain ascii output (instead of cute unicode figures)"
	echo "               This implies ASCII board labels (\"-l\")"
	echo "    -d         Disable colors (only black/white output)"
	echo -e "    \e[4mFollowing options will have no effect while colors are disabled:\e[0m"
	echo -e "    -A \e[2mNUMBER\e[0m  Color code of first player (Default: \e[2m$colorPlayerA\e[0m)"
	echo -e "    -B \e[2mNUMBER\e[0m  Color code of second player (Default: \e[2m$colorPlayerB\e[0m)"
	echo "    -n         Use normal (instead of color filled) figures"
	echo "    -m         Disable color marking of possible moves"
	echo
	echo -e "\e[2m(Default values/options should suit most systems - only if you encounter a"
	echo -e "problem you should have a further investigation of these script parameters."
	echo -e "Or just switch to a real chess game with great graphics and ai! ;)\e[0m"
	echo
}

# Parse command line arguments
while getopts ":a:A:b:B:c:P:s:t:w:dghilmMnpvVz" options; do
	case $options in
		a )	if [[ -z "$OPTARG" ]] ; then
				echo "No valid name for first player specified!" >&2
				exit 1
			# IPv4 && IPv6 validation, source: http://stackoverflow.com/a/9221063
			elif validIP "$OPTARG" ; then
				remote=-1
				remoteip="$OPTARG"
			else
				namePlayerA="$OPTARG"
			fi
			;;
		A )	if ! getColor "$OPTARG" ; then
				colorPlayerA=$?
			else
				echo "'$OPTARG' is not a valid color!" >&2
				exit 1
			fi
			;;
		b )	if [[ -z "$OPTARG" ]] ; then
				echo "No valid name for second player specified!" >&2
				exit 1
			elif [[ "${OPTARG,,}" == "$remotekeyword" ]] ; then
				remote=1
			else
				namePlayerB="$OPTARG"
			fi
			;;
		B )	if ! getColor "$OPTARG" ; then
				colorPlayerB=$?
			else
				echo "'$OPTARG' is not a valid color!" >&2
				exit 1
			fi
			;;
		s )	if validNumber "$OPTARG" ; then
				strength=$OPTARG
			else
				echo "'$OPTARG' is not a valid strength!" >&2
				exit 1
			fi
			;;
		P )	if validPort "$OPTARG" ; then
				port=$OPTARG
			else
				echo "'$OPTARG' is not a valid gaming port!" >&2
				exit 1
			fi
			;;
		w )	if validNumber "$OPTARG" ; then
				sleep=$OPTARG
			else
				echo "'$OPTARG' is not a valid waiting time!" >&2
				exit 1
			fi
			;;
		c )	if [[ -z "$OPTARG" ]] ; then
				echo "No valid path for cache file!" >&2
				exit 1
			else
				cache="$OPTARG"
			fi
			;;
		t )	if validNumber "$OPTARG" ; then
				computer=$OPTARG
			else
				echo "'$OPTARG' is not a valid number for steps!" >&2
				exit 1
			fi
			;;
		d )	color=false
			;;
		g )	guiconfig=true
			;;
		l )	unicodelabels=false
			;;
		n )	colorFill=false
			;;
		m )	colorHelper=false
			;;
		M )	mouse=false
			;;
		p )	ascii=true
			unicodelabels=false
			LC_ALL=C
			;;
		i )	warnings=true
			;;
		v )	version
			exit 0
			;;
		V )	cursor=false
			;;
		z )	require gzip
			require zcat
			cachecompress=true
			;;
		h )	help
			exit 0
			;;
		\?)
			echo -e "Invalid option: -$OPTARG\nFor help, run ./$0 -h" >&2
			exit 1
			;;
	esac
done

# get terminal dimension
echo -en '\e[18t'
if read -r -d "t" -s -t 1 tmp ; then
	termDim=("${tmp//;/ }")
	termWidth=${termDim[2]}
else
	termWidth=80
fi

# gui config
if $guiconfig ; then

	# find a dialog system
	if type gdialog >/dev/null 2>&1 ; then
		dlgtool="gdialog"
		dlgh=0
		dlgw=100
	elif type dialog >/dev/null 2>&1 ; then
		dlgtool="dialog"
		dlgh=0
		dlgw=0
	elif type whiptail >/dev/null 2>&1 ; then
		dlgtool="whiptail"
		dlgh=0
		dlgw=$(( termWidth-10 ))
	else
		dlgtool=""
		error "The graphical configuration requires gdialog/zenity, dialog or at least whiptail - but none of them was found on your system. You have to use the arguments to configure the game unless you install one of the required tools..."
	fi

	# Output the type of the first player in a readable string
	function typeOfPlayerA() {
		if [[ "$remote" -eq "-1" ]] ; then
			echo "Connect to $remoteip (Port $port)"
			return 2
		elif isAI $A ; then
			echo "Artificial Intelligence (with strength $strength)"
			return 1
		else
			echo "Human named $namePlayerA"
			return 0
		fi
	}

	# Output the type of the second player in a readable string
	function typeOfPlayerB() {
		if [[ "$remote" -eq "1" ]] ; then
			echo "Host server at port $port"
			return 2
		elif isAI $B ; then
			echo "Artificial Intelligence (with strength $strength)"
			return 1
		else
			echo "Human named $namePlayerB"
			return 0
		fi
	}

	# Execute a dialog
	# Params: Dialog params (variable length)
	# Prints: Dialog output seperated by new lines
	# Returns the dialog program return or 255 if no dialog tool available
	function dlg() {
		if [[ -n "$dlgtool" ]] ; then
			$dlgtool --backtitle "ChessBash" "$@" 3>&1 1>&2 2>&3 | sed -e "s/|/\n/g" | sort -u
			return "${PIPESTATUS[0]}"
		else
			return 255
		fi
	}

	# Print a message box with a warning/error message
	# Params:
	#	$1	Message
	function dlgerror() {
		#TODO: normal error
		dlg --msgbox "$1" $dlgh $dlgw
	}

	# Start the dialog configuration
	# Neither params nor return, this is just a function for hiding local variables!
	function dlgconfig() {
		local option_mainmenu_playerA="First Player"
		local option_mainmenu_playerB="Second Player"
		local option_mainmenu_settings="Game settings"
		local dlg_on="ON"
		local dlg_off="OFF"

		declare -a option_player=( "Human" "Computer" "Network" )
		declare -a option_settings=( "Color support" "Unicode support" "Verbose Messages" "Mouse support" "AI Cache" )

		local dlg_main
		while dlg_main=$(dlg --ok-button "Edit" --cancel-button "Start Game" --menu "New Game" $dlgh $dlgw 0 "$option_mainmenu_playerA" "$(typeOfPlayerA || true)" "$option_mainmenu_playerB" "$(typeOfPlayerB || true )" "$option_mainmenu_settings" "Color, Unicode, Mouse & AI Cache") ; do
			case "$dlg_main" in

				# Player A settings
				"$option_mainmenu_playerA" )
					typeOfPlayerA > /dev/null
					local type=$?
					local dlg_player
					dlg_player=$(dlg --nocancel --default-item "${option_player[$type]}" --menu "$option_mainmenu_playerA" $dlgh $dlgw 0 "${option_player[0]}" "$( isAI $A && echo "$option_mainmenu_playerA" || echo "$namePlayerA" )" "${option_player[1]}" "with AI (of strength $strength)" "${option_player[2]}" "Connect to Server $remoteip" )
					case "$dlg_player" in
						# Human --> get Name
						*"${option_player[0]}"* )
							[[ "$remote" -eq "-1" ]] && remote=0
							local dlg_namePlayer
							dlg_namePlayer=$(dlg --inputbox "Name of $option_mainmenu_playerA" $dlgh $dlgw "$( isAI $A && echo "$option_mainmenu_playerA" || echo "$namePlayerA" )") && namePlayerA="$dlg_namePlayer"
							;;
						# Computer --> get Strength
						*"${option_player[1]}"* )
							[[ "$remote" -eq "-1" ]] && remote=0
							namePlayerA=$aikeyword
							local dlg_strength
							if dlg_strength=$(dlg --inputbox "Strength of Computer" $dlgh $dlgw  "$strength") ; then
								if validNumber "$dlg_strength" ; then
									strength=$dlg_strength
								else
									dlgerror "Your input '$dlg_strength' is not a valid number!"
								fi
							fi
							;;
						# Network --> get Server and Port
						*"${option_player[2]}"* )
							local dlg_remoteip
							if dlg_remoteip=$(dlg --inputbox "IP(v4 or v6) address of Server" $dlgh $dlgw "$remoteip") ; then
								if validIP "$dlg_remoteip" ; then
									remote=-1
									remoteip="$dlg_remoteip"
									local dlg_networkport
									if dlg_networkport=$(dlg --inputbox "Server Port (non privileged)" $dlgh $dlgw "$port") ; then
										 if validPort "$dlg_networkport" ; then
											port=$dlg_networkport
										else
											dlgerror "Your input '$dlg_remoteip' is not a valid Port!"
										fi
									fi
								else
									dlgerror "Your input '$dlg_remoteip' is no valid IP address!"
									continue
								fi
							fi
							;;
					esac
					# Player color
					if $color ; then
						local colorlist=""
						local c
						for (( c=1; c<7; c++ )) ; do
							colorlist+=" ${colors[$c]^} figures"
						done
						local dlg_player_color
						if dlg_player_color=$(dlg --nocancel --default-item "${colors[$colorPlayerA]^}" --menu "Color of $option_mainmenu_playerA" $dlgh $dlgw 0 "$colorlist") ; then
							getColor "$dlg_player_color" || colorPlayerA=$?
						fi
					fi
					;;

				# Player B settings
				"$option_mainmenu_playerB" )
					typeOfPlayerB > /dev/null
					local type=$?
					local dlg_player
					dlg_player=$(dlg --nocancel --default-item "${option_player[$type]}" --menu "$option_mainmenu_playerB" $dlgh $dlgw 0 "${option_player[0]}" "$( isAI $B && echo "$option_mainmenu_playerB" || echo "$namePlayerB" )" "${option_player[1]}" "with AI (of strength $strength)" "${option_player[2]}" "Wait for connections on port $port" )
					case "$dlg_player" in
						# Human --> get Name
						*"${option_player[0]}"* )
							[[ "$remote" -eq "1" ]] && remote=0
							local dlg_namePlayer
							dlg_namePlayer=$(dlg --inputbox "Name of $option_mainmenu_playerB" $dlgh $dlgw "$( isAI $B && echo "$option_mainmenu_playerB" || echo "$namePlayerB" )") && namePlayerA="$dlg_namePlayer"
							;;
						# Computer --> get Strength
						*"${option_player[1]}"* )
							[[ "$remote" -eq "1" ]] && remote=0
							namePlayerB=$aikeyword
							local dlg_strength
							if dlg_strength=$(dlg --inputbox "Strength of Computer" $dlgh $dlgw  "$strength") ; then
								if validNumber "$dlg_strength" ; then
									strength=$dlg_strength
								else
									dlgerror "Your input '$dlg_strength' is not a valid number!"
								fi
							fi
							;;
						# Network --> get Server and Port
						*"${option_player[2]}"* )
							remote=1
							local dlg_networkport
							if dlg_networkport=$(dlg --inputbox "Server Port (non privileged)" $dlgh $dlgw "$port") ; then
								 if validPort "$dlg_networkport" ; then
									port=$dlg_networkport
								else
									dlgerror "Your input '$dlg_remoteip' is not a valid Port!"
								fi
							fi
							;;
					esac
					# Player color
					if $color ; then
						local colorlist=""
						local c
						for (( c=1; c<7; c++ )) ; do
							colorlist+=" ${colors[$c]^} figures"
						done
						local dlg_player_color
						if dlg_player_color=$(dlg --nocancel --default-item "${colors[$colorPlayerB]^}" --menu "Color of $option_mainmenu_playerB" $dlgh $dlgw 0 "$colorlist") ; then
							getColor "$dlg_player_color" || colorPlayerB=$?
						fi
					fi
					;;

				# Game settings
				"$option_mainmenu_settings" )
					if dlg_settings=$(dlg --separate-output --checklist "$option_mainmenu_settings" $dlgh $dlgw $dlgw "${option_settings[0]}" "with movements and figures" "$($color && echo $dlg_on || echo $dlg_off)" "${option_settings[1]}" "optional including board labels" "$($ascii && echo $dlg_off || echo $dlg_on)" "${option_settings[2]}" "be chatty" "$($warnings && echo $dlg_on || echo $dlg_off)" "${option_settings[3]}" "be clicky" "$($mouse && echo $dlg_on || echo $dlg_off)" "${option_settings[4]}" "in a regluar file" "$([[ -n "$cache" ]] && echo $dlg_on || echo $dlg_off)" ) ; then
						# Color support
						if [[ "$dlg_settings" == *"${option_settings[0]}"* ]] ; then
							color=true
							dlg --yesno "Enable movement helper (colorize possible move)?" $dlgh $dlgw && colorHelper=true || colorHelper=false
							dlg --yesno "Use filled (instead of outlined) figures for both player?" $dlgh $dlgw && colorFill=true || colorFill=false
						else
							color=false
							colorFill=false
							colorHelper=false
						fi
						# Unicode support
						if [[ "$dlg_settings" == *"${option_settings[1]}"* ]] ; then
							ascii=false
							( dlg --yesno "Use Unicode for board labels?" $dlgh $dlgw ) && unicodelabels=true || unicodelabels=false
						else
							ascii=true
							unicodelabels=false
						fi
						# Verbose messages
						[[ "$dlg_settings" == *"${option_settings[2]}"* ]] && warnings=true || warnings=false
						# Mouse support
						[[ "$dlg_settings" == *"${option_settings[3]}"* ]] && mouse=true || mouse=false
						# AI Cache
						local dlg_cache
						if [[ "$dlg_settings" == *"${option_settings[4]}"* ]] && dlg_cache=$(dlg --inputbox "Cache file:" $dlgh $dlgw "$([[ -z "$cache" ]] && echo "$(pwd)/chessbash.cache" || echo "$cache")") && [[ -n "$dlg_cache" ]] ; then
							cache="$dlg_cache"
							type gzip >/dev/null 2>&1 && type zcat >/dev/null 2>&1 && dlg --yesno "Use GZip compression for Cache?" $dlgh $dlgw && cachecompress=true || cachecompress=false
						else
							cache=""
						fi
						# Waiting time (ask always)
						local dlg_sleep
						if dlg_sleep=$(dlg --inputbox "How long should every message be displayed (in seconds)?" $dlgh $dlgw "$sleep") ; then
							if validNumber "$dlg_sleep" ; then
								sleep=$dlg_sleep
							else
								dlgerror "Your input '$dlg_sleep' is not a valid number!"
							fi
						fi
					fi
					;;

				# Other --> exit (gdialog)
				* )
					break
					;;
			esac
		done
	}

	# start config dialog
	dlgconfig
fi

# Save screen
if $cursor ; then
	echo -e "\e7\e[s\e[?47h\e[?25l\e[2J\e[H"
fi

# lookup tables
declare -A cacheLookup
declare -A cacheFlag
declare -A cacheDepth

# associative arrays are faster than numeric ones and way more readable
declare -A redraw
if $cursor ; then
	for (( y=0; y<10; y++ )) ; do
		for (( x=-2; x<8; x++ )) ; do
			redraw[$y,$x]=""
		done
	done
fi

# array to set and get the piece type per coordinates [y,x]
declare -A field

# board start position
# initialize setting - first row
declare -a initline=( 4  2  3  5  6  3  2  4 )
for (( x=0; x<8; x++ )) ; do
	# set pieces at row 1
	field[0,$x]=${initline[$x]}
	# set pawns at row 2
	field[1,$x]=1
  # set empty squares from row 3 up to row 6
	for (( y=2; y<6; y++ )) ; do
		field[$y,$x]=0
	done
	# set pawns at row 7
  field[6,$x]=-1
	# set pieces at row 8
	field[7,$x]=$(( (-1) * ${initline[$x]} ))
done

# readable figure names
declare -a figNames=( "(empty)" "pawn" "knight" "bishop" "rook" "queen" "king" )
# ascii figure names (for ascii output)
declare -a asciiNames=( "k" "q" "r" "b" "n" "p" " " "P" "N" "B" "R" "Q" "K" )

# Evaluaton
# References:
# https://www.chessprogramming.org/Evaluation
# https://www.chessprogramming.org/Point_Value
# https://en.wikipedia.org/wiki/Chess_piece_relative_value
#
# Point value basic evaluation:
# figure weight (for heuristic)
#declare -a figValues=( 0 1 5 5 6 17 42 )
declare -a figValues=( 0 1 3 3 5 9 42 )
#declare -a figValues=( 0 100 320 330 500 900 10000 )

# Warning message on invalid moves (Helper)
# Params:
#	$1	message
# (no return value)
function warn() {
	message="\e[41m\e[1m$1\e[0m\n"
	draw
}

# Readable coordinates
# Params:
#	$1	row / rank position
#	$2	column / file position
# Writes coordinates to stdout
function coord() {
	#echo -en "\x$((41 + $2))$((8 - $1))" # uppercase
	echo -en "\x$((61 + $2))$((8 - $1))"  # lowercase
}

# Get name of player
# Params:
#	$1	player
# Writes name to stdout
function namePlayer() {
	if (( $1 < 0 )) ; then
		if $color ; then
			echo -en "\e[3${colorPlayerA}m"
		fi
		if isAI "$1" ; then
			echo -n "$aiPlayerA"
		else
			echo -n "$namePlayerA"
		fi
	else
		if $color ; then
			echo -en "\e[3${colorPlayerB}m"
		fi
		if isAI "$1" ; then
			echo -n "$aiPlayerB"
		else
			echo -n "$namePlayerB"
		fi
	fi
	if $color ; then
		echo -en "\e[0m"
	fi
}

# Get name of figure
# Params:
#	$1	figure
# Writes name to stdout
function nameFigure() {
	if (( $1 < 0 )) ; then
		echo -n "${figNames[$1*(-1)]}"
	else
		echo -n "${figNames[$1]}"
	fi
}

# Check win/loose position
# (player has king?)
# Params:
#	$1	player
# Return status code 1 if no king
function hasKing() {
	local player=$1;
	local x
	local y
	for (( y=0;y<8;y++ )) ; do
		for (( x=0;x<8;x++ )) ; do
			if (( ${field[$y,$x]} * player == 6 )) ; then
				return 0
			fi
		done
	done
	return 1
}

# Check validity of a concrete single movement
# Params:
#	$1	origin Y position
#	$2	origin X position
#	$3	target Y position
#	$4	target X position
#	$5	current player
# Returns status code 0 if move is valid
function canMove() {
	local fromY=$1
	local fromX=$2
	local toY=$3
	local toX=$4
	local player=$5

	local i
	if (( fromY < 0 || fromY >= 8 || fromX < 0 || fromX >= 8 || toY < 0 || toY >= 8 || toX < 0 || toX >= 8 || ( fromY == toY && fromX == toX ) )) ; then
		return 1
	fi
	local from=${field[$fromY,$fromX]}
	local to=${field[$toY,$toX]}
	local fig=$(( from * player ))
	if (( from == 0 || from * player < 0 || to * player > 0 || player * player != 1 )) ; then
		return 1
	# pawn
	elif (( fig == 1 )) ; then
		if (( fromX == toX && to == 0 && ( toY - fromY == player || ( toY - fromY == 2 * player && ${field["$((player + fromY)),$fromX"]} == 0 && fromY == ( player > 0 ? 1 : 6 ) ) ) )) ; then
				return 0
			else
				return $(( ! ( (fromX - toX) * (fromX - toX) == 1 && toY - fromY == player && to * player < 0 ) ))
		fi
	# queen, rook and bishop
	elif (( fig == 5 || fig == 4  || fig == 3 )) ; then
		# rook - and queen
		if (( fig != 3 )) ; then
			if (( fromX == toX )) ; then
				for (( i = ( fromY < toY ? fromY : toY ) + 1 ; i < ( fromY > toY ? fromY : toY ) ; i++ )) ; do
					if (( ${field[$i,$fromX]} != 0 )) ; then
						return 1
					fi
				done
				return 0
			elif (( fromY == toY )) ; then
				for (( i = ( fromX < toX ? fromX : toX ) + 1 ; i < ( fromX > toX ? fromX : toX ) ; i++ )) ; do
						if (( ${field[$fromY,$i]} != 0 )) ; then
							return 1
						fi
				done
				return 0
			fi
		fi
		# bishop - and queen
		if (( fig != 4 )) ; then
			if (( ( fromY - toY ) * ( fromY - toY ) != ( fromX - toX ) * ( fromX - toX ) )) ; then
				return 1
			fi
			for (( i = 1 ; i < ( fromY > toY ? fromY - toY : toY - fromY) ; i++ )) ; do
				if (( ${field[$((fromY + i * (toY - fromY > 0 ? 1 : -1 ) )),$(( fromX + i * (toX - fromX > 0 ? 1 : -1 ) ))]} != 0 )) ; then
					return 1
				fi
			done
			return 0
		fi
		# nothing found? wrong move.
		return 1
	# knight
	elif (( fig == 2 )) ; then
		return $(( ! ( ( ( fromY - toY == 2 || fromY - toY == -2) && ( fromX - toX == 1 || fromX - toX == -1 ) ) || ( ( fromY - toY == 1 || fromY - toY == -1) && ( fromX - toX == 2 || fromX - toX == -2 ) ) ) ))
	# king
	elif (( fig == 6 )) ; then
		return $(( !( ( ( fromX - toX ) * ( fromX - toX ) ) <= 1 &&  ( ( fromY - toY ) * ( fromY - toY ) ) <= 1 ) ))
	# invalid figure
	else
		error "Invalid figure '$from'!"
		exit 1
	fi
}


# minimax (game theory) algorithm for evaluate possible movements
# (the heart of your computer enemy)
# currently based on negamax with alpha/beta pruning and transposition tables liked described in
# http://en.wikipedia.org/wiki/Negamax#NegaMax_with_Alpha_Beta_Pruning_and_Transposition_Tables
# Params:
#	$1	current search depth
#	$2	alpha (for pruning)
#	$3	beta (for pruning)
#	$4	current moving player
#	$5	preserves the best move (for ai) if true
# Returns best value as status code
# negamax "$strength" 0 255 "$player" true
function negamax() {
	LC_ALL=C
	local depth=$1
	local a=$2
	local b=$3
	local player=$4
	local save=$5
	# transposition table
	local aSave=$a
	local hash
	hash="$player ${field[*]}"
	if ! $save && test "${cacheLookup[$hash]+set}" && (( ${cacheDepth[$hash]} >= depth )) ; then
		local value=${cacheLookup[$hash]}
		local flag=${cacheFlag[$hash]}
		if (( flag == 0 )) ; then
			return "$value"
		elif (( flag == 1 && value > a )) ; then
			a=$value
		elif (( flag == -1 && value < b )) ; then
			b=$value
		fi
		if (( a >= b )) ; then
			return "$value"
		fi
	fi
	# lost own king?
	if ! hasKing "$player" ; then
		cacheLookup[$hash]=$(( strength - depth + 1 ))
		cacheDepth[$hash]=$depth
		cacheFlag[$hash]=0
		return $(( strength - depth + 1 ))
	# use heuristics in depth
	elif (( depth <= 0 )) ; then
		local values=0
		for (( y=0; y<8; y++ )) ; do
			for (( x=0; x<8; x++ )) ; do
				local fig=${field[$y,$x]}
				if (( ${field[$y,$x]} != 0 )) ; then
					local figPlayer=$(( fig < 0 ? -1 : 1 ))
					# a more simple heuristic would be values=$(( $values + $fig ))

					# figPlayer: white=1, black =-1
					# fig: piece number identifier
					# figValues: material piece value
					# ${figValues[$fig]} * figPlayer = material total value

					#(( values += ${figValues[$fig]} * figPlayer ))
					(( values += ${figValues[$fig * $figPlayer]} * figPlayer ))

					# pawns near to end are better
					if (( fig == 1 )) ; then
						if (( figPlayer > 0 )) ; then
							(( values += ( y - 1 ) / 2 ))
						else
							(( values -= ( 6 + y ) / 2 ))
						fi
					fi
				fi
			done
		done
		values=$(( 127 + ( player * values ) ))
		# ensure valid bash return range [0-255]
		if (( values > 253 - strength )) ; then
			values=$(( 253 - strength ))
		elif (( values < 2 + strength )) ; then
			values=$(( 2 + strength ))
		fi
		cacheLookup[$hash]=$values
		cacheDepth[$hash]=0
		cacheFlag[$hash]=0
		return $values
	# calculate best move
	else
		local bestVal=0
		local fromY
		local fromX
		local toY
		local toX
		local i
		local j
		for (( fromY=0; fromY<8; fromY++ )) ; do
			for (( fromX=0; fromX<8; fromX++ )) ; do
				local fig=$(( ${field[$fromY,$fromX]} * ( player ) ))
				# precalc possible fields (faster then checking every 8*8 again)
				local targetY=()
				local targetX=()
				local t=0
				# empty or enemy
				if (( fig <= 0 )) ; then
					continue
				# pawn
				elif (( fig == 1 )) ; then
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX ))
					(( t += 1 ))
					targetY[$t]=$(( 2 * player + fromY ))
					targetX[$t]=$(( fromX ))
					(( t += 1 ))
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX + 1 ))
					(( t += 1 ))
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX - 1 ))
					(( t += 1 ))
				# knight
				elif (( fig == 2 )) ; then
					for (( i=-1 ; i<=1 ; i=i+2 )) ; do
						for (( j=-1 ; j<=1 ; j=j+2 )) ; do
							targetY[$t]=$(( fromY + 1 * i ))
							targetX[$t]=$(( fromX + 2 * j ))
							(( t + 1 ))
							targetY[$t]=$(( fromY + 2 * i ))
							targetX[$t]=$(( fromX + 1 * j ))
							(( t + 1 ))
						done
					done
				# king
				elif (( fig == 6 )) ; then
					for (( i=-1 ; i<=1 ; i++ )) ; do
						for (( j=-1 ; j<=1 ; j++ )) ; do
							targetY[$t]=$(( fromY + i ))
							targetX[$t]=$(( fromX + j ))
							(( t += 1 ))
						done
					done
				else
					# bishop or queen
					if (( fig != 4 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( i != 0 )) ; then
								# can be done nicer but avoiding two loops!
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
							fi
						done
					fi
					# rook or queen
					if (( fig != 3 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( i != 0 )) ; then
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX ))
								(( t += 1 ))
								targetY[$t]=$(( fromY ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
							fi
						done
					fi
				fi
				# process all available moves
				for (( j=0; j < t; j++ )) ; do
					local toY=${targetY[$j]}
					local toX=${targetX[$j]}
					# move is valid
					if (( toY >= 0 && toY < 8 && toX >= 0 && toX < 8 )) &&  canMove "$fromY" "$fromX" "$toY" "$toX" "$player" ; then
						local oldFrom=${field[$fromY,$fromX]};
						local oldTo=${field[$toY,$toX]};
						field[$fromY,$fromX]=0
						field[$toY,$toX]=$oldFrom
						# pawn to queen
						if (( oldFrom == player && toY == ( player > 0 ? 7 : 0 ) )) ;then
							field["$toY,$toX"]=$(( 5 * player ))
						fi
						# recursion
						negamax $(( depth - 1 )) $(( 255 - b )) $(( 255 - a )) $(( player * (-1) )) false
						local val=$(( 255 - $? ))
						field[$fromY,$fromX]=$oldFrom
						field[$toY,$toX]=$oldTo
						if (( val > bestVal )) ; then
							bestVal=$val
							if $save ; then
								selectedX=$fromX
								selectedY=$fromY
								selectedNewX=$toX
								selectedNewY=$toY
							fi
						fi
						if (( val > a )) ; then
							a=$val
						fi
						if (( a >= b )) ; then
							break 3
						fi
					fi
				done
			done
		done
		cacheLookup[$hash]=$bestVal
		cacheDepth[$hash]=$depth
		if (( bestVal <= aSave )) ; then
			cacheFlag[$hash]=1
		elif (( bestVal >= b )) ; then
			cacheFlag[$hash]=-1
		else
			cacheFlag[$hash]=0
		fi
		return $bestVal
	fi
#set +x
}

# Perform a concrete single movement
# Params:
# 	$1	current player
# Globals:
#	$selectedY
#	$selectedX
#	$selectedNewY
#	$selectedNewX
# Return status code 0 if movement was successfully performed
function move() {
	local player=$1
	if canMove "$selectedY" "$selectedX" "$selectedNewY" "$selectedNewX" "$player" ; then
		local fig=${field[$selectedY,$selectedX]}
		field[$selectedY,$selectedX]=0
		field[$selectedNewY,$selectedNewX]=$fig
		# pawn to queen
		if (( fig == player && selectedNewY == ( player > 0 ? 7 : 0 ) )) ; then
			field[$selectedNewY,$selectedNewX]=$(( 5 * player ))
		fi
		return 0
	fi
	return 1
}

# Unicode helper function (for draw)
# Params:
#	$1	first hex unicode character number
#	$2	second hex unicode character number
#	$3	third hex unicode character number
#	$4	integer offset of third hex
# Outputs escape character
function unicode() {
	if ! $ascii ; then
		printf '\\x%s\\x%s\\x%x' "$1" "$2" "$(( 0x$3 + ( $4 ) ))"
	fi
}

# Ascii helper function (for draw)
# Params:
#	$1	decimal ascii character number
# Outputs escape character
function ascii() {
	echo -en "\x$1"
}

# Get ascii code number of character
# Params:
#	$1	ascii character
# Outputs decimal ascii character number
function ord() {
	LC_CTYPE=C printf '%d' "'$1"
}

# Audio and visual bell
# No params or return
function bell() {
	if (( lastBell != SECONDS )) ; then
		echo -en "\a\e[?5h"
		sleep 0.1
		echo -en "\e[?5l"
		lastBell=$SECONDS
	fi
}

# Draw one field (of the gameboard)
# Params:
#	$1	y coordinate
#	$2	x coordinate
#	$3	true if cursor should be moved to position
# Outputs formated field content
function drawField(){
	local y=$1
	local x=$2
	echo -en "\e[0m"
	# move coursor to absolute position
	if $3 ; then
		local yScr=$(( y + originY ))
		local xScr=$(( x * 2 + originX ))
		if $ascii && (( x >= 0 )) ; then
			local xScr=$(( x * 3 + originX ))
		fi
		echo -en "\e[${yScr};${xScr}H"
	fi
	# draw vertical labels
	if (( x==labelX && y >= 0 && y < 8)) ; then
		if $hoverInit && (( hoverY == y )) ; then
			if $color ; then
				echo -en "\e[3${colorHover}m"
			else
				echo -en "\e[4m"
			fi
		elif (( selectedY == y )) ; then
			if ! $color ; then
				echo -en "\e[2m"
			elif (( ${field[$selectedY,$selectedX]} < 0 )) ; then
				echo -en "\e[3${colorPlayerA}m"
			else
				echo -en "\e[3${colorPlayerB}m"
			fi
		fi
		# line number (alpha numeric)
		if $unicodelabels ; then
			echo -en "$(unicode e2 9e 87 -"$y" )\e[0m "
		else
			if $ascii ; then
				echo -n " "
			fi
			echo -en "\x$((38 - y))\e[0m "
		fi
		# clear format
	# draw horizontal labels
	elif (( x>=0 && y==labelY )) ; then
		if $hoverInit && (( hoverX == x )) ; then
			if $color ; then
				echo -en "\e[3${colorHover}m"
			else
				echo -en "\e[4m"
			fi
		elif (( selectedX == x )) ; then
			if ! $color ; then
				echo -en "\e[2m"
			elif (( ${field[$selectedY,$selectedX]} < 0 )) ; then
				echo -en "\e[3${colorPlayerA}m"
			else
				echo -en "\e[3${colorPlayerB}m"
			fi
		else
			echo -en "\e[0m"
		fi
		# row labels
		if $unicodelabels ; then
			#echo -en "$(unicode e2 92 b6 "$x") " # uppercase
			echo -en "$(unicode e2 93 90 "$x") "  # lowercase
		else
			#echo -en " \x$((41 + x))"  # uppercase
			echo -en " \x$((61 + x))"   # lowercase
		fi
	# draw field
	elif (( y >=0 && y < 8 && x >= 0 && x < 8 )) ; then
		local f=${field["$y,$x"]}
		local black=false
		if (( ( x + y ) % 2 == 0 )) ; then
			local black=true
		fi
		# black/white fields
		if $black ; then
			if $color ; then
				echo -en "\e[47;107m"
			else
				echo -en "\e[7m"
			fi
		else
			$color && echo -en "\e[40m"
		fi
		# background
		if $hoverInit && (( hoverX == x && hoverY == y )) ; then
			if ! $color ; then
				echo -en "\e[4m"
			elif $black ; then
				echo -en "\e[4${colorHover};10${colorHover}m"
			else
				echo -en "\e[4${colorHover}m"
			fi
		elif (( selectedX != -1 && selectedY != -1 )) ; then
			local selectedPlayer=$(( ${field[$selectedY,$selectedX]} > 0 ? 1 : -1 ))
			if (( selectedX == x && selectedY == y )) ; then
				if ! $color ; then
					echo -en "\e[2m"
				elif $black ; then
					echo -en "\e[47m"
				else
					echo -en "\e[40;100m"
				fi
			elif $color && $colorHelper && canMove "$selectedY" "$selectedX" "$y" "$x" "$selectedPlayer" ; then
				if $black ; then
					if (( selectedPlayer < 0 )) ; then
						echo -en "\e[4${colorPlayerA};10${colorPlayerA}m"
					else
						echo -en "\e[4${colorPlayerB};10${colorPlayerB}m"
					fi
				else
					if (( selectedPlayer < 0 )) ; then
						echo -en "\e[4${colorPlayerA}m"
					else
						echo -en "\e[4${colorPlayerB}m"
					fi
				fi
			fi
		fi
		# empty field?
		if ! $ascii && (( f == 0 )) ; then
			echo -en "  "
		else
			# figure colors
			if $color ; then
				if (( selectedX == x && selectedY == y )) ; then
					if (( f < 0 )) ; then
						echo -en "\e[3${colorPlayerA}m"
					else
						echo -en "\e[3${colorPlayerB}m"
					fi
				else
					if (( f < 0 )) ; then
						echo -en "\e[3${colorPlayerA};9${colorPlayerA}m"
					else
						echo -en "\e[3${colorPlayerB};9${colorPlayerB}m"
					fi
				fi
			fi
			# unicode figures
			if $ascii ; then
				echo -en " \e[1m${asciiNames[ $f + 6 ]} "
			elif (( f > 0 )) ; then
				if $color && $colorFill ; then
					echo -en "$( unicode e2 99 a0 -$f ) "
				else
					echo -en "$( unicode e2 99 9a -$f ) "
				fi
			else
				echo -en "$( unicode e2 99 a0 $f ) "
			fi
		fi
	# three empty chars
	elif $ascii && (( x >= 0 )) ; then
		echo -n "   "
	# otherwise: two empty chars (on unicode boards)
	else
		echo -n "  "
	fi
	# clear format
	echo -en "\e[0m\e[8m"
}

# Draw the battlefield
# (no params / return value)
function draw() {
	local ty
	local tx
	$useStty && stty -echo
	$cursor || echo -e "\e[2J"
	echo -e "\e[H\e[?25l\e[0m\n\e[K$title\e[0m\n\e[K"
	for (( ty=0; ty<10; ty++ )) ; do
		for (( tx=-2; tx<8; tx++ )) ; do
			if $cursor ; then
				local t
				t="$(drawField "$ty" "$tx" true)"
				if [[ "${redraw[$ty,$tx]}" != "$t" ]]; then
					echo -n "$t"
					redraw[$ty,$tx]="$t"
				fi
			else
				drawField "$ty" "$tx" false
			fi
		done
		$cursor || echo ""
	done
	$useStty && stty echo
	# clear format
	echo -en "\e[0m\e[$(( originY + 10 ));0H\e[2K\n\e[2K$message\e[8m"
}

# Read the next move coordinates
# from keyboard (direct access or cursor keypad)
# or use mouse input (if available)
# Returns 0 on success and 1 on abort
function inputCoord(){
	inputY=-1
	inputX=-1
	local ret=0
	local t
	local tx
	local ty
	local oldHoverX=$hoverX
	local oldHoverY=$hoverY
	IFS=''
	$useStty && stty echo
	if $mouse ; then
		echo -en "\e[?9h"
	fi
	while (( inputY < 0 || inputY >= 8 || inputX < 0  || inputX >= 8 )) ; do
		read -r -sN1 a
		case "$a" in
			$'\e' )
				if read -r -t0.1 -sN2 b ; then
					case "$b" in
						'[A' | 'OA' )
							hoverInit=true
							if (( --hoverY < 0 )) ; then
								hoverY=0
								bell
							fi
							;;
						'[B' | 'OB' )
							hoverInit=true
							if (( ++hoverY > 7 )) ; then
								hoverY=7
								bell
							fi
							;;
						'[C' | 'OC' )
							hoverInit=true
							if (( ++hoverX > 7 )) ; then
								hoverX=7
								bell
							fi
							;;
						'[D' | 'OD' )
							hoverInit=true
							if (( --hoverX < 0 )) ; then
								hoverX=0
								bell
							fi
							;;
						'[3' )
							ret=1
							bell
							break
							;;
						'[5' )
							hoverInit=true
							if (( hoverY == 0 )) ; then
								bell
							else
								hoverY=0
							fi
							;;
						'[6' )
							hoverInit=true
							if (( hoverY == 7 )) ; then
								bell
							else
								hoverY=7
							fi
							;;
						'OH' )
							hoverInit=true
							if (( hoverX == 0 )) ; then
								bell
							else
								hoverX=0
							fi
							;;
						'OF' )
							hoverInit=true
							if (( hoverX == 7 )) ; then
								bell
							else
								hoverX=7
							fi
							;;
						'[M' )
							read -r -sN1 t
							read -r -sN1 tx
							read -r -sN1 ty
							ty=$(( $(ord "$ty" ) - 32 - originY ))
							if $ascii ; then
								tx=$(( ( $(ord "$tx" ) - 32 - originX) / 3 ))
							else
								tx=$(( ( $(ord "$tx" ) - 32 - originX) / 2 ))
							fi
							if (( tx >= 0 && tx < 8 && ty >= 0 && ty < 8 )) ; then
								inputY=$ty
								inputX=$tx
								hoverY=$ty
								hoverX=$tx
							else
								ret=1
								bell
								break
							fi
							;;
						* )
							bell
					esac
				else
					ret=1
					bell
					break
				fi
				;;
			$'\t' | $'\n' | ' ' )
				if $hoverInit ; then
					inputY=$hoverY
					inputX=$hoverX
				fi
				;;
			'~' )
				;;
			$'\x7f' | $'\b' )
				ret=1
				bell
				break
				;;
			[A-Ha-h] )
				t=$(ord "$a")
				if (( t < 90 )) ; then
					inputX=$(( t - 65 ))
				else
					inputX=$(( t - 97 ))
				fi
				hoverX=$inputX
				;;
			[1-8] )
				inputY=$(( 8 - a ))
				hoverY=$inputY
				;;
			* )
				bell
				;;
		esac
		if $hoverInit && (( oldHoverX != hoverX || oldHoverY != hoverY )) ; then
			oldHoverX=$hoverX
			oldHoverY=$hoverY
			draw
		fi
	done
	if $mouse ; then
		echo -en "\e[?9l"
	fi
	$useStty && stty -echo
	return $ret
	#set +x
}

# Player input
# (reads a valid user movement)
# Params
# 	$1	current (user) player
# Returns status code 0
function input() {
	local player=$1
	SECONDS=0
	message="\e[1m$(namePlayer "$player")\e[0m: Move your figure"
	while true ; do
		selectedY=-1
		selectedX=-1
		title="It's $(namePlayer "$player")s turn"
		draw >&3
		if inputCoord ; then
			selectedY=$inputY
			selectedX=$inputX
			if (( ${field["$selectedY,$selectedX"]} == 0 )) ; then
				warn "You cannot choose an empty field!" >&3
			elif (( ${field["$selectedY,$selectedX"]} * player  < 0 )) ; then
				warn "You cannot choose your enemies figures!" >&3
			else
				send "$player" "$selectedY" "$selectedX"
				local figName
				figName=$(nameFigure ${field[$selectedY,$selectedX]} )
				message="\e[1m$(namePlayer "$player")\e[0m: Move your \e[3m$figName\e[0m at $(coord "$selectedY" "$selectedX") to"
				draw >&3
				if inputCoord ; then
					selectedNewY=$inputY
					selectedNewX=$inputX
					if (( selectedNewY == selectedY && selectedNewX == selectedX )) ; then
						warn "You didn't move..." >&3
					elif (( ${field[$selectedNewY,$selectedNewX]} * player > 0 )) ; then
						warn "You cannot kill your own figures!" >&3
					elif move "$player" ; then
						title="$(namePlayer "$player") moved the \e[3m$figName\e[0m from $(coord "$selectedY" "$selectedX") to $(coord "$selectedNewY" "$selectedNewX") \e[2m(took him $SECONDS seconds)\e[0m"
					send "$player" "$selectedNewY" "$selectedNewX"
						return 0
					else
						warn "This move is not allowed!" >&3
					fi
					# Same position again --> revoke
					send "$player" "$selectedY" "$selectedX"
				fi
			fi
		fi
	done
	#set +x
}

# AI interaction
# (calculating movement)
# Params
# 	$1	current (ai) player
# Verbose movement messages to stdout
function ai() {
	local player=$1
	local val
	SECONDS=0
	title="It's $(namePlayer "$player")s turn"
	message="Computer player \e[1m$(namePlayer "$player")\e[0m is thinking..."
	draw >&3
	negamax "$strength" 0 255 "$player" true
	val=$?
	local figName
	figName=$(nameFigure ${field[$selectedY,$selectedX]} )
	message="\e[1m$( namePlayer "$player" )\e[0m moves the \e[3m$figName\e[0m at $(coord "$selectedY" "$selectedX")..."
	draw >&3
	send "$player" "$selectedY" "$selectedX"
	sleep "$sleep"
	if move "$player" ; then
		message="\e[1m$( namePlayer "$player" )\e[0m moves the \e[3m$figName\e[0m at $(coord "$selectedY" "$selectedX") to $(coord "$selectedNewY" "$selectedNewX")"
		draw >&3
		send "$player" "$selectedNewY" "$selectedNewX"
		sleep "$sleep"
		title="$( namePlayer "$player" ) moved the $figName from $(coord "$selectedY" "$selectedX") to $(coord "$selectedNewY" "$selectedNewX" ) (took him $SECONDS seconds)."
	else
		error "AI produced invalid move - that should not hapen!"
	fi
}

# Read column from remote
# Returns column (0-7) as status code
function receiveX() {
	local i
	while true; do
		read -r -n 1 i
		case $i in
			[hH] ) return 7 ;;
			[gG] ) return 6 ;;
			[fF] ) return 5 ;;
			[eE] ) return 4 ;;
			[dD] ) return 3 ;;
			[cC] ) return 2 ;;
			[bB] ) return 1 ;;
			[aA] ) return 0 ;;
			* )
				if $warnings ; then
					warn "Invalid input '$i' for column from network (character between 'A' and 'H' required)!"
				fi
		esac
	done
}

# Read row from remote
# Returns row (0-7) as status code
function receiveY() {
	local i
	while true; do
		read -r -n 1 i
		case $i in
			[1-8] ) return $(( i - 1 )) ;;
			* )
				if $warnings ; then
					warn "Invalid input '$i' for row from network (character between '1' and '8' required)!"
				fi
		esac
	done
}

# receive movement from connected player
# (no params/return value)
function receive() {
	local player=$remote
	SECONDS=0
	title="It's $(namePlayer "$player")s turn"
	message="Network player \e[1m$(namePlayer "$player")\e[0m is thinking... (or sleeping?)"
	draw >&3
	while true ; do
		receiveY
		selectedY=$?
		receiveX
		selectedX=$?
		local figName
		figName=$(nameFigure ${field[$selectedY,$selectedX]} )
		message="\e[1m$( namePlayer "$player" )\e[0m moves the \e[3m$figName\e[0m at $(coord $selectedY $selectedX)..."
		draw >&3
		receiveY
		selectedNewY=$?
		receiveX
		selectedNewX=$?
		if (( selectedNewY == selectedY && selectedNewX == selectedX )) ; then
			selectedY=-1
			selectedX=-1
			selectedNewY=-1
			selectedNewX=-1
			message="\e[1m$( namePlayer "$player" )\e[0m revoked his move... okay, that'll be time consuming"
			draw >&3
		else
			break
		fi
	done
	if move $player ; then
		message="\e[1m$( namePlayer "$player" )\e[0m moves the \e[3m$figName\e[0m at $(coord $selectedY $selectedX) to $(coord $selectedNewY $selectedNewX)"
		draw >&3
		sleep "$sleep"
		title="$( namePlayer $player ) moved the $figName from $(coord $selectedY $selectedX) to $(coord $selectedNewY $selectedNewX) (took him $SECONDS seconds)."
	else
		error "Received invalid move from network - that should not hapen!"
	fi
}

# Write coordinates to network
# Params:
#	$1	player
#	$2	row
#	$3	column
# (no return value/exit code)
function send() {
	local player=$1
	local y=$2
	local x=$3
	if (( remote == player * (-1) )) ; then
		sleep "$remotedelay"
		coord "$y" "$x"
		echo
		sleep "$remotedelay"
	fi
}

# Import transposition tables
# by reading serialised cache from stdin
# (no params / return value)
function importCache() {
	while IFS=$'\t' read -r hash lookup depth flag ; do
		cacheLookup["$hash"]=$lookup
		cacheDepth["$hash"]=$depth
		cacheFlag["$hash"]=$flag
	done
}

# Export transposition tables
# Outputs serialised cache (to stdout)
# (no params / return value)
function exportCache() {
	for hash in "${!cacheLookup[@]}" ; do
		echo -e "$hash\t${cacheLookup[$hash]}\t${cacheDepth[$hash]}\t${cacheFlag[$hash]}"
	done
}

# Trap function for exporting cache
# (no params / return value)
function exitCache() {
	# permanent cache: export
	if [[ -n "$cache" ]] ; then
		echo -en "\r\n\e[2mExporting cache..." >&3
		if $cachecompress ; then
			exportCache | gzip > "$cache"
		else
			exportCache > "$cache"
		fi
		echo -e " done!\e[0m" >&3
	fi
}

# Perform necessary tasks for exit
# like deleting files and measuring runtime
# (no params / return value)
function end() {
	# remove pipe
	if [[ -n "$fifopipe" && -p "$fifopipe" ]] ; then
		rm "$fifopipe"
	fi
	# disable mouse
	if $mouse ; then
		echo -en "\e[?9l"
	fi
	# enable input
	stty echo
	# restore screen
	if $cursor ; then
		echo -en "\e[2J\e[?47l\e[?25h\e[u\e8"
	fi
	# exit message
	duration=$(( $( date +%s%N ) - timestamp ))
	seconds=$(( duration / 1000000000 ))
	echo -e "\r\n\e[2mYou've wasted $seconds,$(( duration -( seconds * 1000000000 ))) seconds of your lifetime playing with a Bash script.\e[0m\n"
}

# Exit trap
trap "end" 0

# setting up requirements for network
piper="cat"
fifopipe="/dev/fd/1"
initializedGameLoop=true
if (( remote != 0 )) ; then
	require nc
	require mknod
	initializedGameLoop=false
	if (( remote == 1 )) ; then
		fifopipe="$fifopipeprefix.server"
		piper="nc -l $port"
	else
		fifopipe="$fifopipeprefix.client"
		piper="nc $remoteip $port"
		echo -e "\e[1mWait!\e[0mPlease make sure the Host (the other Player) has started before continuing.\e[0m"
		anyKey
	fi
	if [[ ! -e "$fifopipe" ]] ; then
		mkfifo "$fifopipe"
	fi
	if [[ ! -p "$fifopipe" ]] ; then
		echo "Could not create FIFO pipe '$fifopipe'!" >&2
	fi
fi

# print welcome title
title="Welcome to ChessBa.sh"
if isAI "1" || isAI "-1" ; then
	title="$title - your room heater tool!"
fi

# permanent cache: import
if [[ -n "$cache" && -f "$cache" ]] ; then
	echo -en "\n\n\e[2mImporting cache..."
	if $cachecompress ; then
		importCache < <( zcat "$cache" )
	else
		importCache < "$cache"
	fi
	echo -e " done\e[0m"
fi

# main game loop
{
	p=1
	while true ; do
		# initialize remote connection on first run
		if ! $initializedGameLoop ; then
			# set cache export trap
			trap "exitCache" 0
			warn "Waiting for the other network player to be ready..." >&3
			# exchange names
			if (( remote == -1 )) ; then
				read -r namePlayerA < $fifopipe
				echo "$namePlayerB"
				echo "connected with first player." >&3
			elif (( remote == 1 )) ; then
				echo "$namePlayerA"
				read -r namePlayerB < $fifopipe
				echo "connected with second player." >&3
			fi
			# set this loop initialized
			initializedGameLoop=true
		fi
		# reset global variables
		selectedY=-1
		selectedX=-1
		selectedNewY=-1
		selectedNewX=-1
		# switch current player
		(( p *= (-1) ))
		# check check (or: if the king is lost)
		if hasKing "$p" ; then
			if (( remote == p )) ; then
				receive < $fifopipe
			elif isAI "$p" ; then
				if (( computer-- == 0 )) ; then
					echo "Stopping - performed all ai steps" >&3
					exit 0
				fi
				ai "$p"
			else
				input "$p"
			fi
		else
			title="Game Over!"
			message="\e[1m$(namePlayer $(( p * (-1) )) ) wins the game!\e[1m\n"
			draw >&3
			anyKey
			exit 0
		fi
	done | $piper > "$fifopipe"

	# check exit code
	netcatExit=$?
	gameLoopExit=${PIPESTATUS[0]}
	if (( netcatExit != 0 )) ; then
		error "Network failure!"
	elif (( gameLoopExit != 0 )) ; then
		error "The game ended unexpected!"
	fi
} 3>&1
