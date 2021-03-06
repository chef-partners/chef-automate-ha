#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts begin ---
#/ Usage:
#/  Do the following from this directory to deploy a new cluster to AZURE_RESOURCE_GROUP:
#/      ./deploy_clients.sh --resource-group <AZURE_RESOURCE_GROUP>
#/
#/  Do the following if your --template-directoy lives somewhere else
#/  ./deploy_clients.sh --template-directory <ARM_DIRECTORY> --resource-group <AZURE_RESOURCE_GROUP>
#/
#/ Description:
#/  This script will deploy a chef-automate-ha cluster given 3 mandatory flags:
#/  the azure resource group (--resource-group), the chef-automate-ha template directory
#/  (--template-directory), and an --argsfile which is a json object of key parameters
#/  necessary for the deployment
#/
#/ Examples:
#/  Run the following command in the current directory to create a new cluster
#/  under a resource group called "myAutomateResourceGroup"
#/
#/    ./deploy_clients.sh \
#/      --resource-group "myAutomateResourceGroup" \
#/      --argfile "args.json"
#/
#/  By default the resource group will be cleansed after 7 days, so make sure to add the
#/  --keep flag to keep your resource group indefinitely.  For example
#/
#/    ./deploy_clients.sh \
#/      --keep \
#/      --resource-group "myAutomateResourceGroup" \
#/      --argfile "args.json"
#/ Options:
#/   --help: Display this help message
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

# Setup logging
readonly LOG_FILE="/tmp/$(basename "$0").log"
readonly DATE_FORMAT="+%Y-%m-%d_%H:%M:%S.%2N"
info()    { echo "[$(date ${DATE_FORMAT})] [INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[$(date ${DATE_FORMAT})] [WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[$(date ${DATE_FORMAT})] [ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[$(date ${DATE_FORMAT})] [FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename "${__file}" .sh)"

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

# initialize flag variables
ARG_FILE="${__dir}/output/args.json"
# initialize JSON variables picked up from the --argfile
sshClientUser=""
sshClientDns=""
# initialize catchall for non-flagged parameters
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -d|--debug)
      set -o xtrace
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    -A|--argfile)
      ARG_FILE=$2
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

# If the ARG_FILE has been specified and the file exists read in the arguments
if [[ "X${ARG_FILE}" != "X" ]]; then
  if [[ ( -f $ARG_FILE ) ]]; then
    info "$(echo "Reading JSON vars from ${ARG_FILE}:"; cat "${ARG_FILE}" )"

    VARS=$(cat ${ARG_FILE} | jq -r '. | keys[] as $k | "\($k)=\"\(.[$k])\""')
    info "$(echo "Evaluating the following bash variables:"; echo "${VARS}")"

    # Evaluate all the vars in the arguments
    while read -r line; do
      eval "$line"
    done <<< "$VARS"
  else
    fatal "Unable to find specified args file: ${ARG_FILE}"
  fi
fi

# fail of mandatory JSON fields in the --argfile aren't set
if [[ "$sshClientUser" == "" ]]; then fatal "sshClientUser must be defined in the args.json"; fi
if [[ "$sshClientDns" == "" ]]; then fatal "sshClientDns must be defined in the args.json"; fi
if [[ "$azureResourceGroupForChefServer" == "" ]]; then fatal "azureResourceGroupForChefServer must be defined in the args.json"; fi

# fail if any positional parameters appear; they should be preceeded with a flag
eval set -- "$PARAMS"
if [[ "${PARAMS}" != "" ]]; then
  errorMessage=$(echo "The following parameters [${PARAMS}] do not have flags. See the following usage:"; usage)
  fatal "${errorMessage}"
fi

# --- Helper scripts end ---

_bootstrapTheClient(){
  # create a subshell to initialize knife with the chefserver
  info "bootstrapping the client"
  (
    # cd to the knife bootstrapper directory
    cd "${__dir}/../knife/bootstrapper/${azureResourceGroupForChefServer}"

    # get the IP for the public DNS of the the client
    local ipOfClient=""; ipOfClient=$(dig +short "${sshClientDns}")

    # call the bootstrap script
    local command="./doKnifeBootstrap.sh --client-ip ${ipOfClient} --client-user ${sshClientUser}"
    info "${command}"

    eval "${command}"
  )
}

main() {
  _bootstrapTheClient
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main
fi

