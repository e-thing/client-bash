#!/bin/bash -e
# EThing Command Line Interface
###############################################################################
#set -e          # exit on command errors (so you MUST handle exit codes properly!)
#set -E          # pass trap handlers down to subshells
#set -o pipefail # capture fail exit codes in piped commands
#set -x         # execution tracing debug messages

# Error handler
on_err() {
	echo ">> ERROR: $?"
	FN=0
	for LN in "${BASH_LINENO[@]}"; do
		[ "${FUNCNAME[$FN]}" = "main" ] && break
		echo ">> ${BASH_SOURCE[$FN]} $LN ${FUNCNAME[$FN]}"
		FN=$(( FN + 1 ))
	done
}
trap on_err ERR

# Exit handler
declare -a EXIT_CMDS
add_exit_cmd() { EXIT_CMDS+="$*;  "; }
on_exit(){ eval "${EXIT_CMDS[@]}"; }
trap on_exit EXIT

# Get command info
CMD_PWD=$(pwd)
CMD="$0"
CMD_DIR="$(cd "$(dirname "$CMD")" && pwd -P)"

# Defaults and command line options
VERBOSE=
DEBUG=
APIKEY=
APIURL="http://localhost/ething/api"
USER="ething" # default for basic authentication
PASSWORD=
CONF=~/.ething



# Basic helpers
out() { echo "$(date +%Y%m%dT%H%M%SZ): $*"; }
err() { out "$*" 1>&2; }
vrb() { [ ! "$VERBOSE" ] || out "$@"; }
dbg() { [ ! "$DEBUG" ] || err "$@"; }
die() { err "EXIT: $1" && [ "$2" ] && [ "$2" -ge 0 ] && exit "$2" || exit 1; }

# Show help function to be used below
show_help() {
	echo 
	echo "USAGE: $(basename "$CMD") [global args] <command> [command args]"
	
	# print the arguments definition from the code
	awk 'BEGIN{argsection=0;}{
		
		if($1=="#@desc"){
			d=substr($0,index($0,"#@desc")+7);
			
			print "";
			nlines=split_str(d,lines);
			for(i=1;i<=nlines;i++)
				print lines[i];
		}
		
		if($1=="#@args"){
			argsection=1;
			d=substr($0,index($0,"#@args")+7);
			match(d,/^(\t| )*/);
			argpad=substr(d,1,RLENGTH);
			print "";
			print d;
		}
		
		if(argsection && match($0,/^(\t| )*-.*\).*#/)){
			arg=substr($0,1,index($0,"#")-1);
			com=substr($0,index($0,"#")+1);
			
			sub(/\|/,", ",arg);
			sub(/\)(\t| )*$/,"",arg);
			sub(/(^(\t| )*)/,"",arg);
			sub(/(^(\t| )*)|((\t| )*$)/,"",com);
			
			printf("%s  %-16s ",argpad,arg);
			
			nlines=split_str(com,comlines);
			for(i=1;i<=nlines;i++){
				if(i>1)
					printf("%s                   ",argpad);
				print comlines[i];
			}
			
		}
		
		if(argsection && index($0,"esac"))
			argsection=0;
	}
	
	function split_str(str,result){
		match(str,/^(\t| )*/);
		pad=substr(str,1,RLENGTH);
		str=substr(str,RLENGTH+1);
		i=0
		while(length(str) && ++i < 100){
			if(length(str)>50){
				t=substr(str,1,50);
				m=match(t,/[^a-zA-Z0-9][a-zA-Z0-9]*$/);
				if(m==0) m=50;
			}
			else
				m=50;
			result[i]=pad""substr(str,1,m);
			str=substr(str,m+1);
		}
		return i;
	}' "$CMD"
}


getConfKey() {
	if [ -s "${CONF}" ] ; then
		grep "^${1}=" "${CONF}" | awk -F'=' '{print $2;}'
	fi
}


loadConf() {
	
	local v
		
	v=$(getConfKey "apiurl") || true;
	if [ -n "${v}" ] ; then
		APIURL="${v}"
	fi
	v=$(getConfKey "apikey") || true;
	if [ -n "${v}" ] ; then
		APIKEY="${v}"
	fi
	v=$(getConfKey "password") || true;
	if [ -n "${v}" ] ; then
		PASSWORD="${v}"
	fi
	
}

loadConf



#@args global arguments:
NARGS=-1; while [ "$#" -ne "$NARGS" ]; do NARGS=$#; case $1 in
	
	-h|--help)      # This help message
		show_help; exit 1; ;;
	-d|--debug)     # Enable debugging messages (implies verbose)
		DEBUG=$(( DEBUG + 1 )) && VERBOSE="$DEBUG" && shift && echo "#-INFO: DEBUG=$DEBUG (implies VERBOSE=$VERBOSE)"; ;;
	-v|--verbose)   # Enable verbose messages
		VERBOSE=$(( VERBOSE + 1 )) && shift && echo "#-INFO: VERBOSE=$VERBOSE"; ;;
	
	-u|--api-url)     # Define the url of the EThing API to access to
		shift && APIURL="$1" && shift && vrb "#-INFO: APIURL=$APIURL"; ;;
	-k|--api-key)     # Define the API key for this request
		shift && APIKEY="$1" && shift && vrb "#-INFO: APIKEY=$APIKEY"; ;;
	--password)      # auth password
		shift && PASSWORD="$1" && shift && vrb "#-INFO: PASSWORD=$PASSWORD"; ;;
	-*)
		err "Unknown global argument $1"
		show_help
		exit 1;;
	*)
		break;
esac; done

#[ "$DEBUG" ]  &&  set -x

[ -n "${APIURL}" ] && vrb "#-INFO: APIURL=$APIURL"
[ -n "${APIKEY}" ] && vrb "#-INFO: APIKEY=$APIKEY"
[ -n "${USER}" ] && vrb "#-INFO: USER=$USER"
[ -n "${PASSWORD}" ] && vrb "#-INFO: PASSWORD=$PASSWORD"

#helpers

curlfn(){
	
	local auth=1
	local continue_on_list=""
	local out
	
	while [ $# -ne 0 ]; do case $1 in
		-no-auth)   
			auth=0 && shift; ;;
		-continue-on-*) 
			continue_on_list+=" ${1#-continue-on-}" && shift; ;;
		-o) 
			shift; out="${1}" && shift; dbg "#-DBG: out=$out"; ;;
		*)
			break;
	esac; done

	local -a curl_args
	
	if [ "${auth}" -eq 1 ] ; then
		if [ "$APIKEY" ] ; then
			curl_args+=("-H" "X-API-KEY: ${APIKEY}")
		elif [ -n "${USER}" ] && [ -n "${PASSWORD}" ] ; then
			curl_args+=("--user" "${USER}:${PASSWORD}")
		else
			err "no authentication set !"
			exit 1
		fi
	fi
	
	while [ $# -ne 0 ]; do 
		if [[ "${1}" == "/"* ]] ; then
			curl_args+=("${APIURL}${1}")
		else
			curl_args+=("${1}")
		fi
		shift
	done
	
	dbg "curl" "${curl_args[@]}"
	
	tmpf=/tmp/curl_out_${$}
	> "${tmpf}"
	
	HTTP_STATUS=$(curl -w "%{http_code}" -o "${tmpf}" "${curl_args[@]}")
	
	dbg "curl exit code $?"
	dbg "HTTP_STATUS:${HTTP_STATUS}"
	
	
	if [ $(echo ${HTTP_STATUS} | grep -c '^[45]') -ne 0 ] ; then
		# an error occurs
		dbg "$(cat "${tmpf}")"
		err "ERROR ${HTTP_STATUS} : $(cat "${tmpf}" | getKey "message")"
		[ $(echo ${continue_on_list} | grep -wc ${HTTP_STATUS}) -eq 0 ] && exit 1
		return 1
	else
		# success
		if [ -n "${out}" ] ; then
			local dir="$(dirname "${out}")"
			if [ ! -d "${dir}" ] ; then
				dbg "#-DBG: create dir '${dir}'"
				mkdir -p "${dir}"
				[ $? -ne 0 ] && err "unable to create the output file ${out}" && exit 1
			fi
			mv "${tmpf}" "${out}"
			[ $? -ne 0 ] && err "unable to create the output file ${out}" && exit 1
		else
			cat "${tmpf}"
			echo ""
			\rm -f "${tmpf}"
		fi
		
	fi
}



rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"
}

isId() {
  echo "${1}" | egrep -c '^[0-9a-zA-Z_-]{7}$'
}



getKey() {
	grep -Po '"'"${1}"'": *(""|".*[^\\]"|.+)(,|}|$)' | awk '{s=substr($0,index($0,":")+1); sub(/^ *"?/,"",s); sub(/"? *(,|})?$/,"",s); print s;}'
}



# command definition

#@desc 
#@desc Available commands :

auth() {
	curlfn -no-auth -s "/auth/authorize" -H "Content-Type: application/json" -X POST -d '{"user":"'"${USER}"'","password":"'"${PASSWORD}"'"}' | getKey "token"
}


#@desc connect
#@desc   This command allows you to start a new session and save it for further requests.
connect() {
	
	while [ $# -ne 0 ]; do case $1 in
		*)
			err "Unknown $0 argument $1"
			show_help
			exit 1;;
	esac; done
	
	if [ -n "${APIKEY}" ] ; then
		echo -e "apiurl=${APIURL}\napikey=${APIKEY}" > "${CONF}"
	elif [ -n "${USER}" ] && [ -n "${PASSWORD}" ] ; then
		echo -e "apiurl=${APIURL}\npassword=${PASSWORD}" > "${CONF}"
	else
		err "no authentication credentials provided"
		err "option --api-key or options --user --password must be set"
		exit 1
	fi
	
}


#@desc usage
#@desc   This command allows you to get information about the space usage.
usage(){
	
	curlfn -s "/usage"
	
}

#@desc profile
#@desc   This command allows you to get information about your profile.
profile(){
	
	curlfn -s "/profile"
	
}

#@desc list
#@desc   This command allows you to list resources.
list(){
	
	dbg "#-DBG: list command";
	
	local qstr=""
	
	#@args   arguments
	while [ $# -ne 0 ]; do case $1 in
		
		
		-q|--query)      # Query string for searching resources
			shift
			qstr+="&q="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--limit)      # Limits the number of resources returned
			shift
			qstr+="&limit="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--skip)      # Skips a number of resources
			shift
			qstr+="&limit="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--sort)      # The key on which to do the sorting, by default the sort is made by modifiedDate descending. To make the sort descending, prepend the field name by minus '-'. For instance, '-createdDate' will sort by createdDate descending
			shift
			qstr+="&sort="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--fields)      # Only this fields will be returned (comma separated values)
			shift
			qstr+="&fields="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		*)
			err "Unknown $0 argument $1"
			show_help
			exit 1;;
	esac; done
	
	
	curlfn -s "/resources?${qstr#&}"
	
}

#@desc get
#@desc   This command allows you to download resources.
get(){
	
	local -a resources
	local qstr=""
	
	#@args   arguments:
	while [ $# -ne 0 ]; do case $1 in
		
		-f|--format)      # the output format (default to JSON) [only for table]
			shift
			qstr+="&fmt="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		-q|--query)      # Query string for filtering results [only for table]
			shift
			qstr+="&q="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--sort)      # the key on which to do the sorting, by default the sort is made by date ascending. To make the sort descending, prepend the field name by minus '-'. For instance, '-date' will sort by date descending [only for table]
			shift
			qstr+="&sort="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--start)      # Position of the first rows to return. If start is negative, the position will start from the end. (default to 0) [only for table]
			shift
			qstr+="&start="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--length)      # Maximum number of rows to return. If not set, returns until the end. [only for table]
			shift
			qstr+="&length="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		--fields)      # Only this fields will be returned (comma separated values) [only for table]
			shift
			qstr+="&fields="$(rawurlencode "$1")
			shift
			dbg "#-DBG: qstr=$qstr";
			;;
		*)
			resources+=("$1");
			dbg "#-DBG: resources=${resources[@]}";
			shift;
			;;
	esac; done
	
	
	for r in "${resources[@]}"
	do
		
		local m
		
		if [ $(isId "${r}") -eq 0 ] ; then
			# r = filename
			dbg "#-DBG: ${r} --> filename";
			m=$(list --limit 1 --fields "id,name,type" -q "name == '${r}'")
		else
			# r = id
			dbg "#-DBG: ${r} --> id";
			m=$(curlfn -continue-on-404 -s "/resources/${r}?fields=id,name,type")
		fi
		
		local type=$(echo "${m}" | getKey "type" | tr '[A-Z]' '[a-z]')
		local id=$(echo "${m}" | getKey "id")
		local name=$(echo "${m}" | getKey "name")
		
		if [ -z "${id}" ] ; then
			err "resource not found : ${r}"
			continue;
		fi
		
		dbg "#-DBG: ${r} --> ${type} ${id} ${name}";
		
		curlfn -continue-on-404 -continue-on-403 -o "${name}" "/${type}s/${id}?${qstr#&}"
		
	done
	
	
}


#@desc put
#@desc   This command allows you to upload files.
put(){
	
	local -a localfiles
	local -a distantnames
	local qstr=""
	
	local boundary=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) || true;
	
	while [ $# -ne 0 ]; do case $1 in
		*)
			
			local base="$(echo "${1}" | grep -Eo '^([^\/]*\/)*')" # the part to be removed in the distantname
			local bi=$((${#base} + 1))
			
			dbg "#-INFO: base=${base}";
			dbg "#-INFO: bi=${bi}";
			
			if [ -d "$1" ] ; then
				# directory
				for f in $(\find "$1" -type f) ;do
					localfiles+=("${f}");
					distantnames+=("$(echo "${f}" | cut -c${bi}-)") # remove the base part
				done
			elif [ -f "$1" ] ; then
				# file
				localfiles+=("$1");
				distantnames+=("$(echo "${1}" | cut -c${bi}-)") # remove the base part
			else
				err "invalid file '$1'"
			fi
			shift;
			;;
	esac; done
	
	
	for i in "${!localfiles[@]}"
	do
		
		local localfile="${localfiles[${i}]}"
		local distantname="${distantnames[${i}]}"
		
		local meta="{\"name\": \"${distantname}\"}"
		
		dbg "#-INFO: [${i}] put ${localfile} --> ${distantname}"
		
		( echo -en "--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\nContent-Type: application/octet-stream\r\n\r\n" \
		&& cat "${localfile}" && echo -en "\r\n--${boundary}--\r\n" ) \
			| curlfn "/files" \
			-H "Content-Type: multipart/related; boundary=\"${boundary}\"" \
			--data-binary "@-" > /dev/null # do not print the metadata
		
	done
	
	
}


# get command
[ $# -eq 0 ] && err "no command given" && show_help && exit 1
command=$1 && shift

if [ -z "$(type -t ${command})" ] || [ "$(type -t ${command})" != "function" ] ; then
	err "Unknown command ${command}"
	show_help
	exit 1
fi

${command} "$@"





