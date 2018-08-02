#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts begin ---
#/ Usage:
#/		./doKnifeBootstrap.sh --client-ip 51.141.119.193 --client-user azureuser --chefserver-user delivery --chefserver-org gavinorganization
#/ Description:
#/		Description:
#/ Examples:
#/		./doKnifeBootstrap.sh --client-ip 1.2.3.4 --client-user harry
#/ Options:
#/		--help:      Display this help message
#/		--client-ip:   The IP address of the linux node you want to bootstrap
#/		--client-user: The ssh username for the node (assumes public key authentication already setup)
#/		--chefserver-user:	The user created on the chef server, corresponding to a user.pem file
#/		--chefserver-org: The chefserver organization, e.g.,  fordorganization
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

# Setup logging
readonly LOG_FILE="/tmp/$(basename "$0").log"
readonly DATE_FORMAT="+%Y-%m-%d_%H:%M:%S.%2N"
info()    { echo "[$(date ${DATE_FORMAT})] [INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[$(date ${DATE_FORMAT})] [WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[$(date ${DATE_FORMAT})] [ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[$(date ${DATE_FORMAT})] [FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; kill 0 ; }

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename "${__file}" .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this as it depends on your app

# Run these at the start and end of every script ALWAYS
info "Executing ${__file}"
cleanup() {
    local result=$?
    if (( result  > 0 )); then
        error "Exiting ${__file} prematurely with exit code [${result}]"
    else
        info "Exiting ${__file} cleanly with exit code [${result}]"
    fi
}
trap cleanup EXIT
trap "kill 0" SIGINT

# set flag variables (PARAMS is a collector for any positional arguments that, wrongly, get passed in)
PARAMS=""
CLIENT_IP=""
CLIENT_USERNAME=""
CHEF_SERVER_ORGANIZATION=""
CHEF_SERVER_USER=""
while (( "$#" )); do
  case "$1" in
    -d|--debug)
      set -o xtrace
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    -i|--client-ip)
      CLIENT_IP=$2
      shift 2
      ;;
    -u|--client-user)
      CLIENT_USERNAME=$2
      shift 2
      ;;
    -U|--chefserver-user)
      CHEF_SERVER_USER=$2
      shift 2
      ;;
    -o|--chefserver-org)
      CHEF_SERVER_ORGANIZATION=$2
      shift 2
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      errorMessage=$(echo "Error: Unsupported flag $1"; usage)
      fatal "${errorMessage}"
      ;;
    *) # collect any positional arguments ignoring them
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# fail if mandetory parameters are not present
if [[ "$CLIENT_IP" == "" ]]; then fatal "--client-ip must be defined"; fi
if [[ "$CLIENT_USERNAME" == "" ]]; then fatal "--client-user must be defined"; fi
if [[ "$CHEF_SERVER_USER" == "" ]]; then fatal "--chefserver-user  must be defined"; fi
if [[ "$CHEF_SERVER_ORGANIZATION" == "" ]]; then fatal "--chefserver-org must be defined"; fi
if [[ ! -e "${__dir}/.chef/${CHEF_SERVER_ORGANIZATION}-validator.pem" ]]; then fatal "the chef-server validation private key, used by clients to bootstrap to the chef-server, MUST exist at ${__dir}/.chef/${CHEF_SERVER_ORGANIZATION}-validator.pem"; fi
if [[ ! -e "${__dir}/.chef/${CHEF_SERVER_USER}.pem" ]]; then fatal "the chef-server user private key USER.pem, used by knife for initial connection, MUST exist at ${__dir}/.chef/${CHEF_SERVER_USER}.pem"; fi

# fail if any positional parameters appear; they should be preceeded with a flag
eval set -- "$PARAMS"
if [[ "${PARAMS}" != "" ]]; then
  errorMessage=$(echo "The following parameters [${PARAMS}] do not have flags. See the following usage:"; usage)
  fatal "${errorMessage}"
fi

# --- Helper scripts end ---

_getNodeName() {
	local result=""
	result=$(ssh "${CLIENT_USERNAME}@${CLIENT_IP}" "hostname -f")
	echo "${result}"
}

main() {
    # pre-populate required json argument
	local extraJsonParameter=""
	extraJsonParameter=$(echo {} | jq --compact-output --arg param1 "${CLIENT_IP}" '. | . + {"cloud": {"public_ip": $param1}}')
	info "${extraJsonParameter}"

	# get the node name from the actual node
	local nodeName=""
	nodeName=$(_getNodeName)

	# do the knife bootstrap
	local command="knife bootstrap ${CLIENT_IP} --node-ssl-verify-mode none --verbose --ssh-user ${CLIENT_USERNAME} --sudo --node-name ${nodeName} --run-list 'recipe[starter]' --json-attributes '${extraJsonParameter}'"
	info "Running the following command [${command}]"
  eval "${command}"

  return
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main
fi

