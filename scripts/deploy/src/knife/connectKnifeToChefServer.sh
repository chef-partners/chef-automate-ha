#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts begin ---
#/ Usage:
#/  Do the following from this directory to deploy a new cluster to AZURE_RESOURCE_GROUP:
#/  	./deploy_clients.sh --resource-group <AZURE_RESOURCE_GROUP>
#/
#/  Do the following if your --template-directoy lives somewhere else
#/  ./deploy_clients.sh --template-directory <ARM_DIRECTORY> --resource-group <AZURE_RESOURCE_GROUP>
#/
#/ Description:
#/  This script will deploy a chef-automate-ha cluster given 3 mandetory flags:
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
ARG_FILE="${__dir}/../cluster/output/args.json"
# initialize JSON variables picked up from the --argfile
adminUsername=""
organizationName=""
ownerEmail=""
ownerName=""
azureResourceGroupForChefServer=""
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

# fail of mandetory JSON fields in the --argfile aren't set
if [[ "$adminUsername" == "" ]]; then fatal "adminUsername must be defined in the args.json"; fi
if [[ "$organizationName" == "" ]]; then fatal "organizationName must be defined in the args.json"; fi
if [[ "$ownerEmail" == "" ]]; then fatal "ownerEmail must be defined in the args.json"; fi
if [[ "$ownerName" == "" ]]; then fatal "ownerName must be defined in the args.json"; fi
if [[ "$azureResourceGroupForChefServer" == "" ]]; then fatal "azureResourceGroupForChefServer must be defined in the args.json"; fi

# fail if any positional parameters appear; they should be preceeded with a flag
eval set -- "$PARAMS"
if [[ "${PARAMS}" != "" ]]; then
  errorMessage=$(echo "The following parameters [${PARAMS}] do not have flags. See the following usage:"; usage)
  fatal "${errorMessage}"
fi

# --- Helper scripts end ---
_getClusterOutputForKnifeInput(){
    # create the input directory if it doesn't exist
    if [[ ! -e "${__dir}/input" ]]; then mkdir -p "${__dir}/input"; fi

   	local command="cp -r ${__dir}/../cluster/output/* ${__dir}/input/."

    info "copying the client output: ${command}"
    eval "${command}"
}

_createTheCookiecutterConfigFile(){

    # inject my public key after base64 encoding it
    local transformedAzureParametersFile=""; transformedAzureParametersFile=$(cat "${__dir}/cookiecutter-knife/cookiecutter.json.template")

    # inject the KNIFE_DIR_NAME
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $azureResourceGroupForChefServer '. | .dir_name |= $param1')

    # inject values from the json $ARG_FILE
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $organizationName '. | .chefserver_organization |= $param1')
    local chefServerUserName="delivery"
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $chefServerUserName '. | .chefserver_username |= $param1')
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $chefServerFqdn '. | .chefserver_public_dns |= $param1')

    # create copy of the parameters file for actual deployment
    echo "${transformedAzureParametersFile}" > "${__dir}/cookiecutter-knife/cookiecutter.json"

    return
}

_createTheKnifeBootrappingDirectory(){
  # create a subshell to create the cookiecutter-knife
  (
	  cd "${KNIFE_DIR_NAME}"

	  if [[ ! -e "${KNIFE_DIR_NAME}/${azureResourceGroupForChefServer}" ]]; then
		info "creating the knife ${azureResourceGroupForChefServer} directory"
		cookiecutter --no-input "${__dir}/cookiecutter-knife"
	  else
		info "knife bootrapping directory already present"
	  fi
  )

  info "copying the latest PEM private keys"
  cp -r ${__dir}/input/*.pem ${KNIFE_DIR_NAME}/${azureResourceGroupForChefServer}/.chef/.

  local result="$(tree -a "${KNIFE_DIR_NAME}/${azureResourceGroupForChefServer}")"
  info "knife bootstrap directory is complete: ${result}"
}

_initializeKnifeToTheChefServer(){
  # create a subshell to initialize knife with the chefserver
  info "bootstrapping knife"
  (
    cd "${KNIFE_DIR_NAME}/${azureResourceGroupForChefServer}"
    knife ssl fetch
    knife ssl check
		knife supermarket download audit
		gunzip audit-*.tar.gz
		tar -xvf audit-*.tar --directory cookbooks
    knife cookbook upload starter
    knife cookbook upload audit
  )
}

_bootstrapTheClient(){
  # create a subshell to initialize knife with the chefserver
  info "bootstrapping the client"
  (
    cd "${KNIFE_DIR_NAME}/${azureResourceGroupForChefServer}"

    local ipOfClient=""; ipOfClient=$(dig +short "${sshClientDns}")
    local command=""; command="yes | ./doKnifeBootstrap.sh --client-ip ${ipOfClient} --client-user ${adminUsername} --chefserver-user ${chefServerWebLoginUserName} --chefserver-org ${organizationName}"
    info "${command}"

    eval "${command}"
  )
}

KNIFE_DIR_NAME="${__dir}/bootstrapper"
if [[ ! -e "${KNIFE_DIR_NAME}" ]]; then mkdir -p "${KNIFE_DIR_NAME}"; fi
main() {
  _getClusterOutputForKnifeInput
  _createTheCookiecutterConfigFile
  _createTheKnifeBootrappingDirectory
  _initializeKnifeToTheChefServer
  #_bootstrapTheClient
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main
fi

