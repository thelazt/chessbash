#/bin/bash
#
# Chess Bash
# a simple chess game written in an inappropriate language :)
#
# Copyright (c) 2015 by Bernhard Heinloth <bernhard@heinloth.net>
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Default values
strength=3
namePlayerA="Player"
namePlayerB="AI"
color=true
colorPlayerA=4
colorPlayerB=1
colorHelper=true
colorFill=true
ascii=false
warnings=false
computer=-1
sleep=2
cache=""
cachecompress=false

# Help message
# Writes text to stdout
function help {
	echo "\e[1mChess Bash\e[0m - a small chess game written in Bash"
	echo
	echo "Usage: $0 [options]"
	echo
	echo "Game options"
	echo "    -a NAME    Name of first player - or \"ai\" for computer controlled"
	echo "               (Default: $namePlayerA)"
	echo "    -b NAME    Name of second player - or \"ai\" for computer controlled"
	echo "               (Default: $namePlayerB)"
	echo "    -s NUMBER  Strength of computer (Default: $strength)"
	echo "    -w NUMBER  Waiting time for messages in seconds (Default: $sleep)"
	echo
	echo "Cache management"
	echo "    -c FILE    Makes cache permanent - load and store calculated moves"
	echo "    -z         Compress cache file (only to be used with -c, requires gzip)"
	echo "    -t STEPS   Exit after STEPS ai turns and print time (for benchmark)"
	echo
	echo "Output control"
	echo "    -h         This help message"
	echo "    -i         Enable verbose input warning messages"
	echo "    -p         Plain ascii output (instead of cute unicode figures)"
	echo "    -d         Disable colors (only black/white output)"
	echo "    Following options will have no effect while colors are disabled:"
	echo "    -A NUMBER  Color code of first player (Default: $colorPlayerA)"
	echo "    -B NUMBER  Color code of second player (Default: $colorPlayerB)"
	echo "    -n         Use normal (instead of color filled) figures"
	echo "    -m         Disable color marking of possible moves"
	echo
}

# Parse command line arguments
while getopts ":a:A:b:B:c:s:t:w:dhimnpz" options; do
	case $options in
		a )	if [[ -z "$OPTARG" ]] ;then
				echo "No valid name for first player specified!" >&2
				exit 1
			else
				namePlayerA="$OPTARG"
			fi
			;;
		A )	if [[ "$OPTARG" =~ "^[1-8]$" ]] ;then
				colorPlayerA=$OPTARG
			else
				echo "'$OPTARG' is not a valid color!" >&2
				exit 1
			fi
			;;
		b )	if [[ -z "$OPTARG" ]] ;then
				echo "No valid name for second player specified!" >&2
				exit 1
			else
				namePlayerB="$OPTARG"
			fi
			;;
		B )	if [[ "$OPTARG" =~ ^[1-8]$ ]] ;then
				colorPlayerB=$OPTARG
			else
				echo "'$OPTARG' is not a valid color!" >&2
				exit 1
			fi
			;;
		s )	if [[ "$OPTARG" =~ ^[0-9]+$ ]] ;then
				strength=$OPTARG
			else
				echo "'$OPTARG' is not a valid strength!" >&2
				exit 1
			fi
			;;
		w )	if [[ $OPTARG =~ ^[0-9]+$ ]] ;then
				sleep=$OPTARG
			else
				echo "'$OPTARG' is not a valid waiting time!" >&2
				exit 1
			fi
			;;
		c )	if [[ -z "$OPTARG" ]] ;then
				echo "No valid path for cache file!" >&2
				exit 1
			else
				cache="$OPTARG"
			fi
			;;
		t )	if [[ "$OPTARG" =~ ^[0-9]+$ ]] ;then
				computer=$OPTARG
			else
				echo "'$OPTARG' is not a valid number for steps!" >&2
				exit 1
			fi
			;;
		d )	color=false
			;;
		n )	colorFill=false
			;;
		m )	colorHelper=false
			;;
		p )	ascii=true
			;;
		i )	warnings=true
			;;
		z )	if which gzip && which zcat ; then
				cachecompress=true
			else
				echo "Missing gzip/zcat for compression" >&2
				exit 1
			fi
			;;
		h )	help
			exit 0
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			;;
	esac
done

# internal values
timestamp=$( date +%s%N )
selectedX=-1
selectedY=-1
selectedNewX=-1
selectedNewY=-1
aikeyword="ai"
aiPlayerA="Marvin"
aiPlayerB="R2D2"

# lookup tables
declare -A cacheLookup
declare -A cacheFlag
declare -A cacheDepth

# associative arrays are faster than numeric ones and way more readable
declare -A field

# initialize setting - first row
declare -a initline=( 4  2  3  6  5  3  2  4 )
for (( x=0; x<8; x++ )) ; do
	field[0,$x]=${initline[$x]}
	field[7,$x]=$(( (-1) * ${initline[$x]} ))
done
# set pawns
for (( x=0; x<8; x++ )) ; do
	field[1,$x]=1
	field[6,$x]=-1
done
# set empty fields
for (( y=2; y<6; y++ )) ; do
	for (( x=0; x<8; x++ )) ; do
		field[$y,$x]=0
	done
done

# readable figure names
declare -a figNames=( "(empty)" "pawn" "knight" "bishop" "rook" "queen" "king" )
# ascii figure names (for ascii output)
declare -a asciiNames=( "k" "q" "r" "b" "n" "p" " " "P" "N" "B" "R" "Q" "K" )
# figure weight (for heuristic)
declare -a figValues=( 0 1 5 5 6 17 42 )

# Error message, p.a. on bugs
# Params:
#	$1	message
# (no return value, exit game)
function error() {
	echo "\e[41m\e[1m $1 \e[0m\n\e[3m(Script exit)\e[0m";
	exit 1
}

# Warning message on invalid moves (Helper)
# Params:
#	$1	message
# (no return value)
function warn() {
	echo -e "\r                                                                     \r\e[41m\e[1m$1\e[0m\n"
}

# Readable coordinates
# Params:
#	$1	row position
#	$2	column position
# Writes coordinates to stdout
function coord() {
	echo -en "\x$((48-$1))$(($2+1))"
}

# Check if ai player
# Params:
#	$1	player
# Return status code 0 if ai player
function isAI() {
	if (( $1 < 0 )) ; then
		[ "${namePlayerA,,}" == "$aikeyword" ] && return 0 || return 1
	else
		[ "${namePlayerB,,}" == "$aikeyword" ]  && return 0 || return 1
	fi
}

# Get name of player
# Params:
#	$1	player
# Writes name to stdout
function namePlayer() {
	if (( $1 < 0 )) ; then
		$color && echo -en "\e[3${colorPlayerA}m"
		isAI $1 && echo -n $aiPlayerA || echo -n $namePlayerA
	else
		$color && echo -en "\e[3${colorPlayerB}m"
		isAI $1 && echo -n $aiPlayerB || echo -n $namePlayerB
	fi
	$color && echo -en "\e[37m"
}

# Get name of figure
# Params:
#	$1	figure
# Writes name to stdout
function nameFigure() {
	if (( $1 < 0 )) ; then
		echo -n ${figNames[$1*(-1)]}
	else
		echo -n ${figNames[$1]}
	fi
}

# Check win/loose position
# (player has king?)
# Params:
#	$1	player
# Return status code 1 if no king
function hasKing(){
	local player=$1;
	local x
	local y
	for (( y=0;y<8;y++ )) ; do
		for (( x=0;x<8;x++ )) ; do
			if (( ${field[$y,$x]} * $player == 6 )) ; then
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
	if (( $fromY < 0 || $fromY >= 8 || $fromX < 0 || $fromX >= 8 || $toY < 0 || $toY >= 8 || $toX < 0 || $toX >= 8 || ( $fromY == $toY && $fromX == $toX ) )) ; then
		return 1
	fi
	local from=${field[$fromY,$fromX]}
	local to=${field[$toY,$toX]}
	local fig=$(( $from * $player ))
	if (( $from == 0 || $from*$player < 0 || $to*$player > 0 || $player*$player != 1 )) ; then
		return 1
	# pawn
	elif (( $fig == 1 )) ; then 
		if (( $fromX == $toX && $to == 0 && ( $toY - $fromY == $player || ( $toY - $fromY == 2 * $player && ${field["$(($player + $fromY)),$fromX"]} == 0 && $fromY == ( $player > 0 ? 1 : 6 ) ) ) )) ; then
				return 0
			else 
				return $(( ! ( ($fromX - $toX) * ($fromX - $toX) == 1 && $toY - $fromY == $player && $to * $player < 0 ) )) 
		fi
	# queen, rock and bishop
	elif (( $fig == 5 || $fig == 4  || $fig == 3 )) ; then
		# rock - and queen
		if (( $fig != 3 )) ; then 
			if (( $fromX == $toX )) ; then
				for (( i = ( $fromY < $toY ? $fromY : $toY ) + 1 ; i < ( fromY > toY ? fromY : toY ) ; i++ )) ; do
					if (( ${field[$i,$fromX]} != 0 )) ; then
						return 1
					fi
				done
				return 0
			elif (( $fromY == $toY )) ; then
				for (( i = ( $fromX < $toX ? $fromX : $toX ) + 1 ; i < ( fromX > toX ? fromX : toX ) ; i++ )) ; do
						if (( ${field[$fromY,$i]} != 0 )) ; then
							return 1
						fi
				done
				return 0
			fi
		fi
		# bishop - and queen
		if (( $fig != 4 )) ; then
			if (( ( $fromY - $toY ) * ( $fromY - $toY ) != ( $fromX - $toX ) * ( $fromX - $toX ) )) ; then
				return 1
			fi
			for (( i = 1 ; i < ( $fromY > toY ? $fromY - $toY : $toY - $fromY) ; i++ )) ; do
				if (( ${field[$(($fromY + $i * ($toY - $fromY > 0 ? 1 : -1 ) )),$(( $fromX + $i * ($toX - $fromX > 0 ? 1 : -1 ) ))]} != 0 )) ; then
					return 1
				fi
			done
			return 0
		fi
		# nothing found? wrong move.
		return 1
	# knight
	elif (( $fig == 2 )) ; then 
		return $(( ! ( ( ( $fromY - $toY == 2 || $fromY - $toY == -2) && ( $fromX - $toX == 1 || $fromX - $toX == -1 ) ) || ( ( $fromY - $toY == 1 || $fromY - $toY == -1) && ( $fromX - $toX == 2 || $fromX - $toX == -2 ) ) ) ))
	# king
	elif (( $fig == 6 )) ; then
		return $(( !( ( ( $fromX - $toX ) * ( $fromX - $toX ) ) <= 1 &&  ( ( $fromY - $toY ) * ( $fromY - $toY ) ) <= 1 ) ))
	# invalid figure
	else
		error "Invalid figure '$from'!" >&2
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
function negamax() {
	local depth=$1
	local a=$2
	local b=$3
	local player=$4
	local save=$5
	# transposition table
	local aSave=$a
	local hash="${field[@]}"
	if ! $save && test "${cacheLookup[$hash]+set}" && (( ${cacheDepth[$hash]} >= $depth )) ; then
		local value=${cacheLookup[$hash]}
		local flag=${cacheFlag[$hash]}
		if (( $flag == 0 )) ; then
			return $value
		elif (( $flag == 1 && $value > $a )) ; then
			a=$value
		elif (( $flag == -1 && $value < $b )) ; then
			b=$value
		fi
		if (( $a >= $b )) ; then
			return $value
		fi
	fi
	# lost own king?
	if ! hasKing $player ; then
		cacheLookup[$hash]=1
		cacheDepth[$hash]=$depth
		cacheFlag[$hash]=0
		return 1
	# use heuristics in depth
	elif (( $depth <= 0 )) ; then
		local values=0
		for (( y=0; y<8; y++ )) ; do
			for (( x=0; x<8; x++ )) ; do
				local fig=${field[$y,$x]}
				if (( ${field[$y,$x]} != 0 )) ; then
					local figPlayer=$(( $fig < 0 ? -1 : 1 ))
					# a more simple heuristic would be values=$(( $values + $fig ))
					values=$(( $values + ${figValues[$fig * $figPlayer]} * $figPlayer ))
					# pawns near to end are better
					if (( $fig == 1 )) ; then
						if (( $figPlayer > 0 )) ; then
							values=$(( $values + ( $y - 1 ) / 2 ))
						else
							values=$(( $values - ( 6 + $y ) / 2 ))
						fi
					fi
				fi
			done
		done
		values=$(( 127 + ( $player * $values ) ))
		# ensure valid bash return range
		if (( $values > 254 )) ; then
			values=254
		elif (( $values < 1 )) ; then
			values=1
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
				local fig=$(( ${field[$fromY,$fromX]} * ( $player ) ))
				# precalc possible fields (faster then checking every 8*8 again)
				local targetY=()
				local targetX=()
				local t=0
				# empty or enemy
				if (( $fig <= 0 )) ; then
					continue
				# pawn
				elif (( $fig == 1 )) ; then
					targetY[$t]=$(( $player + $fromY ))
					targetX[$t]=$fromX
					t=$(( $t + 1 ))
					targetY[$t]=$(( 2 * $player + $fromY ))
					targetX[$t]=$fromX
					t=$(( $t + 1 ))
					targetY[$t]=$(( $player + $fromY ))
					targetX[$t]=$(( $fromX + 1 ))
					t=$(( $t + 1 ))
					targetY[$t]=$(( $player + $fromY ))
					targetX[$t]=$(( $fromX - 1 ))
					t=$(( $t + 1 ))
				# knight
				elif (( $fig == 2 )) ; then
					for (( i=-1 ; i<=1 ; i=i+2 )) ; do
						for (( j=-1 ; j<=1 ; j=j+2 )) ; do
							targetY[$t]=$(( $fromY + 1 * $i ))
							targetX[$t]=$(( $fromX + 2 * $j ))
							t=$(( $t + 1 ))
							targetY[$t]=$(( $fromY + 2 * $i ))
							targetX[$t]=$(( $fromX + 1 * $j ))
							t=$(( $t + 1 ))
						done
					done
				# king
				elif (( $fig == 6 )) ; then
					for (( i=-1 ; i<=1 ; i++ )) ; do
						for (( j=-1 ; j<=1 ; j++ )) ; do
							targetY[$t]=$(( $fromY + $i ))
							targetX[$t]=$(( $fromX + $j ))
							t=$(( $t + 1 ))
						done
					done
				else
					# bishop or queen
					if (( $fig != 4 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( $i != 0 )) ; then
								# can be done nicer but avoiding two loops!
								targetY[$t]=$(( $fromY + $i ))
								targetX[$t]=$(( $fromX + $i ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY - $i ))
								targetX[$t]=$(( $fromX - $i ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY + $i ))
								targetX[$t]=$(( $fromX - $i ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY - $i ))
								targetX[$t]=$(( $fromX + $i ))
								t=$(( $t + 1 ))
							fi
						done
					fi
					# rock or queen
					if (( $fig != 3 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( $i != 0 )) ; then
								targetY[$t]=$(( $fromY + $i ))
								targetX[$t]=$(( $fromX ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY - $i ))
								targetX[$t]=$(( $fromX ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY ))
								targetX[$t]=$(( $fromX + $i ))
								t=$(( $t + 1 ))
								targetY[$t]=$(( $fromY ))
								targetX[$t]=$(( $fromX - $i ))
								t=$(( $t + 1 ))
							fi
						done
					fi
				fi
				# process all available moves
				for (( j=0; j<$t; j++ )) ; do
					local toY=${targetY[$j]}
					local toX=${targetX[$j]}
					# move is valid
					if (( $toY >= 0 && $toY < 8 && $toX >= 0 && $toX < 8 )) &&  canMove $fromY $fromX $toY $toX $player ; then
						local oldFrom=${field[$fromY,$fromX]};
						local oldTo=${field[$toY,$toX]};
						field[$fromY,$fromX]=0
						field[$toY,$toX]=$oldFrom
						# pawn to queen
						if (( $oldFrom == $player && $toY == ( $player > 0 ? 7 : 0 ) )) ;then
							field["$toY,$toX"]=$(( 5 * $player )) 
						fi
						# recursion
						negamax $(( $depth - 1 )) $(( 255 - $b )) $(( 255 - $a )) $(( $player * (-1) )) false
						local val=$(( 255 - $? ))
						field[$fromY,$fromX]=$oldFrom
						field[$toY,$toX]=$oldTo
						if (( $val > $bestVal )) ; then
							bestVal=$val
							if $save ; then
								selectedX=$fromX
								selectedY=$fromY
								selectedNewX=$toX
								selectedNewY=$toY
							fi
						fi
						if (( $val > $a )) ; then
							a=$val
						fi
						if (( $a >= $b )) ; then
							break 3
						fi
					fi
				done
			done
		done
		cacheLookup[$hash]=$bestVal
		cacheDepth[$hash]=$depth
		if (( $bestVal <= $aSave )) ; then
			cacheFlag[$hash]=1
		elif (( $bestVal >= $b )) ; then
			cacheFlag[$hash]=-1
		else
			cacheFlag[$hash]=0
		fi
		return $bestVal
	fi
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
function move(){
	local player=$1
	if canMove $selectedY $selectedX $selectedNewY $selectedNewX $player ; then
		local fig=${field[$selectedY,$selectedX]}
		field[$selectedY,$selectedX]=0
		field[$selectedNewY,$selectedNewX]=$fig
		# pawn to queen
		if (( $fig == $player && $selectedNewY == ( $player > 0 ? 7 : 0 ) )) ; then
			field[$selectedNewY,$selectedNewX]=$(( 5 * $player )) 
		fi
		return 0
	fi
	return 1
}

# Unicode helper function (for draw) 
# Params:
#	$1	decimal unicode character number
# Outputs escape character
function unicode() {
	if ! $ascii ; then
		printf '\\u%x\n' $1
	fi
}

# Ascii helper function (for draw) 
# Params:
#	$1	decimal ascii character number
# Outputs escape character
function ascii() {
	echo -en "\x$1"
}

# Draw the battlefield
# (no params / return value)
function draw() {
	echo -e "\e[0m\ec\n\e[2m$message\e[0m\n"
	for (( y=0; y<8; y++ )) ; do
		if (( $selectedY == $y )) ; then
			echo -en "\e[2m"
		fi
		# line number (alpha numeric)
		if $ascii ; then
			echo -en "  \x$((48 - $y))"
		else
			echo -en "  $(unicode $((9405 - $y))) "
		fi
		# clear format
		echo -en "\e[0m  "
		for (( x=0; x<8; x++ )) ; do
			local f=${field["$y,$x"]}
			local black=false
			if (( (x+y)%2 == 0 )) ; then
				local black=true
			fi
			# black/white fields
			if $black ; then
				$color && echo -en "\e[107m" || echo -en "\e[7m"
			else
				$color && echo -en "\e[40m"
			fi
			# background
			if (( $selectedX != -1 && $selectedY != -1 )) ; then
				local selectedPlayer=$(( ${field[$selectedY,$selectedX]} > 0 ? 1 : -1 ))
				if (( $selectedX == $x && $selectedY == $y )) ; then
					if ! $color ; then 
						echo -en "\e[2m"
					elif $black ; then
						echo -en "\e[47m"
					else
						echo -en "\e[100m"
					fi
				elif $color && $colorHelper && canMove $selectedY $selectedX $y $x $selectedPlayer ; then
					if $black ; then
						(( $selectedPlayer < 0 )) && echo -en "\e[10${colorPlayerA}m" || echo -en "\e[10${colorPlayerB}m"
					else
						(( $selectedPlayer < 0 )) && echo -en "\e[4${colorPlayerA}m" || echo -en "\e[4${colorPlayerB}m"
					fi
				fi
			fi
			# empty field?
			if ! $ascii && (( $f == 0 )) ; then
				echo -en " "
			else
				# figure colors
				if $color ; then
					if (( $selectedX == $x && $selectedY == $y )) ; then
						(( $f < 0 )) && echo -en "\e[3${colorPlayerA}m" || echo -en "\e[3${colorPlayerB}m"
					else
						(( $f < 0 )) && echo -en "\e[9${colorPlayerA}m" || echo -en "\e[9${colorPlayerB}m"
					fi
				fi
				# unicode figures
				if $ascii ; then
					echo -en " \e[1m${asciiNames[ $f + 6 ]}"
				elif (( $f > 0 )) ; then
					if $color && $colorFill ; then
						echo -en "$( unicode $(( 9824 - $f )) )"
					else
						echo -en "$( unicode $(( 9818 - $f )) )"
					fi
				else
					echo -en "$( unicode $(( 9824 + $f )) )"
				fi
			fi
			# clear format
			echo -en " \e[0m"
		done
		echo ""
	done
	# numbering
	echo -en "\n     "
	for (( x=0; x<8; x++ )) ; do
		(( $selectedX == $x )) && echo -en "\e[2m" || echo -en "\e[0m"
		if $ascii ; then
			echo -en " \x$((31 + $x)) "
		else
			echo -en " $(unicode $(( 10112 + $x )) )"
		fi
	done
	# clear format
	echo -e "  \e[0m\n"
}

# Read row from user input
# Params:
#	$1	current player
# Returns row (0-7) as status code
function inputY() {
	local i
	while true; do
		echo -en "\r                                                                     \r"
		read -n 1 -p "$1" i
		case $i in
			[8hH] ) return 0 ;;
			[7gG] ) return 1 ;;
			[6fF] ) return 2 ;;
			[5eE] ) return 3 ;;
			[4dD] ) return 4 ;;
			[3cC] ) return 5 ;;
			[2bB] ) return 6 ;;
			[1aA] ) return 7 ;;
			"" ) continue ;;
			* )
				if $warnings ; then
					warn "Invalid input '$i' - please enter a character between 'a' and 'h' for the row!"
				fi
		esac
	done
}

# Read column from user input
# Params:
#	$1	current player
# Returns column (0-7) as status code
function inputX() {
	local i
	while true; do
		echo -en "\r                                                                     \r"
		read -n 1 -p "$1" i
		case $i in
			[1-8] ) return $(( $i - 1 )) ;;
			* )
				if $warnings ; then
					warn "Invalid input '$i' - please enter a character between '1' and '8' for the column!"
				fi
		esac
	done
}

# Player input
# (reads a valid user movement)
# Params
# 	$1	current (user) player
# Returns status code 0
function input() {
	local player=$1
	SECONDS=0
	while true ; do
		selectedY=-1
		selectedX=-1
		draw
		message="(Waiting for `namePlayer $player`s turn)"
		local imsg="$(echo -e "\e[1m`namePlayer $player`\e[0m: Move figure")"
		while true ; do
			inputY "$imsg"
			selectedY=$?
			inputX "$imsg `ascii $(( 48 - $selectedY ))`"
			selectedX=$?
			if (( ${field["$selectedY,$selectedX"]} == 0 )) ; then
				warn "You cannot choose an empty field!"
			elif (( ${field["$selectedY,$selectedX"]} * $player  < 0 )) ; then
				warn "You cannot choose your enemies figures!"
			else
				break
			fi
		done
		draw
		local figName=$(nameFigure ${field[$selectedY,$selectedX]} )
		local imsg="$imsg `coord $selectedY $selectedX` ($figName) to"
		while true ; do
			inputY "$imsg"
			selectedNewY=$?
			inputX "$imsg `ascii $(( 48 - $selectedNewY ))`"
			selectedNewX=$?
			if (( $selectedNewY == $selectedY && $selectedNewX == $selectedX )) ; then
				warn "You didn't move..."
				sleep $sleep
				break
			elif (( ${field[$selectedNewY,$selectedNewX]} * $player > 0 )) ; then
				warn "You cannot kill your own figures!"
			elif move $player ; then
				message="`namePlayer $player` moved the $figName from `coord $selectedY $selectedX` to `coord $selectedNewY $selectedNewX` (took him $SECONDS seconds)."
				return 0
			else
				warn "This move is not allowed!"
			fi
		done
	done
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
	draw
	message="(Waiting for `namePlayer $player`s turn)"
	echo -e "Computer player \e[1m`namePlayer $player`\e[0m is thinking..."
	negamax $strength 0 255 $player
	val=$?
	local figName=$(nameFigure ${field[$selectedY,$selectedX]} )
	draw
	echo -e "\e[1m$( namePlayer $player )\e[0m moves the \e[3m$figName\e[0m at $(coord $selectedY $selectedX)..."
	sleep $sleep
	if move $player ; then
		draw
		echo -e "\e[1m$( namePlayer $player )\e[0m moves the \e[3m$figName\e[0m at $(coord $selectedY $selectedX) to $(coord $selectedNewY $selectedNewX)"
		sleep $sleep
		message="$( namePlayer $player ) moved the $figName from $(coord $selectedY $selectedX) to $(coord $selectedNewY $selectedNewX) (took him $SECONDS seconds)."
	else 
		error "AI produced invalid move - that should not hapen!"
	fi
}

# Import transposition tables
# by reading serialised cache from stdin
# (no params / return value)
function importCache() {
	while IFS=$'\t' read hash lookup depth flag ; do
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

# Perform necessary tasks for exit
# like exporting cache and measuring runtime
# (no params / return value)
function end() {
	# permanent cache: export
	if [[ -n "$cache" ]] ; then
		echo -en "\r\n\e[2mExporting cache..."
		if $cachecompress ; then
			exportCache | gzip > "$cache"
		else
			exportCache > "$cache"
		fi
		echo -e " done!\e[0m"
	fi
	# exit message
	duration=$(( $( date +%s%N ) - $timestamp ))
	seconds=$(( $duration / 1000000000 )) 
	echo -e "\r\n\e[2mYou've wasted $seconds,$(( $duration -( $seconds * 1000000000 ))) seconds of your lifetime playing with a Bash script.\e[0m\n\n\e[1mSee you next time in Chess Bash!\e[0m\n"
}

# set exit trap
trap "end" 0

# print welcome message
message=" Welcome to Chess`unicode 10048` Bash"
if isAI 1 || isAI -1 ; then
	message="$message - your room heater tool!"
fi
echo -e "\ec\n\e[1m$message\e[0m\n\e[2m written 2015 by Bernhard Heinloth\e[0m\n\n (Don't forget: this is just a proof-of-concept!)"
sleep $sleep

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
p=1
while true ; do
	# reset global variables
	selectedX=-1
	selectedY=-1
	selectedNewX=-1
	selectedNewY=-1
	# switch current player
	p=$(( $p * (-1) ))
	# check check (or: if the king is lost)
	if hasKing $p ; then
		if isAI $p ; then
			if (( computer-- == 0 )) ; then
				echo "Stopping - performed all ai steps"
				exit 0
			fi
			ai $p
		else
			input $p
		fi
	else
		message="Game Over!"
		draw
		echo -e "\e[1m`namePlayer $(( $p * (-1) ))` wins the game!\e[1m\n"
		exit 0
	fi
done
