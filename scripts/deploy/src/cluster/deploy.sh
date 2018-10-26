#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts begin ---
#/ Usage:
#/  Do the following from this directory to deploy a new cluster to AZURE_RESOURCE_GROUP:
#/      ./deploy_cluster.sh --resource-group <AZURE_RESOURCE_GROUP>
#/
#/  Do the following if your --template-directoy lives somewhere else
#/  ./deploy_cluster.sh --template-directory <ARM_DIRECTORY> --resource-group <AZURE_RESOURCE_GROUP>
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
#/    ./deploy_cluster.sh \
#/      --resource-group "myAutomateResourceGroup" \
#/      --argfile "args.json"
#/
#/  By default the resource group will be cleansed after 7 days, so make sure to add the
#/  --keep flag to keep your resource group indefinitely.  For example
#/
#/    ./deploy_cluster.sh \
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
ARG_FILE="${__dir}/input/args.json"
keepGroupFromReaper="False"
resourceGroup=""
templateDirectory="$(echo "${__dir}" | sed 's/chef-automate-ha.*/chef-automate-ha/')"
# initialize JSON variables picked up from the --argfile
adminUsername=""
appID=""
baseUrl=""
objectId=""
organizationName=""
ownerEmail=""
ownerName=""
password=""
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
    -t|--template-directory)
      templateDirectory=$2
      shift 2
      ;;
    -r|--resource-group)
      resourceGroup=$2
      shift 2
      ;;
    -k|--keep)
      keepGroupFromReaper="True"
      shift 1
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

# fail if mandatory flags aren't set
if [[ "$resourceGroup" == "" ]]; then fatal "--resource-group flag must be defined"; fi
if [[ "$templateDirectory" == "" ]]; then fatal "--template-directory flag must be defined"; fi
if [[ ! -e "$templateDirectory/azuredeploy.parameters.json" ]]; then fatal "The ARM template root directory [${templateDirectory}] may be incorrect: no azuredeploy.parameters.json was found.  Override this directory with the --template-directory flag"; fi
# fail of mandatory JSON fields in the --argfile aren't set
if [[ "$adminUsername" == "" ]]; then fatal "adminUsername must be defined in the args.json"; fi
if [[ "$appID" == "" ]]; then fatal "appID must be defined in the args.json"; fi
if [[ "$baseUrl" == "" ]]; then fatal "baseUrl must be defined in the args.json"; fi
if [[ "$objectId" == "" ]]; then fatal "objectId must be defined in the args.json"; fi
if [[ "$organizationName" == "" ]]; then fatal "organizationName must be defined in the args.json"; fi
if [[ "$ownerEmail" == "" ]]; then fatal "ownerEmail must be defined in the args.json"; fi
if [[ "$ownerName" == "" ]]; then fatal "ownerName must be defined in the args.json"; fi
if [[ "$password" == "" ]]; then fatal "password must be defined in the args.json"; fi

# fail if any positional parameters appear; they should be preceeded with a flag
eval set -- "$PARAMS"
if [[ "${PARAMS}" != "" ]]; then
  errorMessage=$(echo "The following parameters [${PARAMS}] do not have flags. See the following usage:"; usage)
  fatal "${errorMessage}"
fi

# --- Helper scripts end ---

_createTheDeploymentParameterFile(){
    # inject my public key after base64 encoding it
    local mySshPublicKey=""; mySshPublicKey=$(cat ~/.ssh/id_rsa.pub)
    local transformedAzureParametersFile=""; transformedAzureParametersFile=$(cat "${templateDirectory}/azuredeploy.parameters.json" | jq --arg param1 "$mySshPublicKey" '. | .parameters.sshKeyData.value |= $param1')

    #local customScriptsTimestamp=$(date +%s)
    #transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --argjson param1 $customScriptsTimestamp '. | .parameters.customScriptsTimestamp.value |= $param1')

    #local customScriptsShouldDebug="true"
    #transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --argjson param1 $customScriptsShouldDebug '. | .parameters.customScriptsShouldDebug.value |= $param1')

    # update the objectId
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $objectId '. | .parameters.objectId.value |= $param1')
    # inject the adminUsername
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $adminUsername '. | .parameters.adminUsername.value |= $param1')
    # inject the organization name on chef server
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $organizationName '. | .parameters.organizationName.value |= $param1')
    # inject the appID
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $appID '. | .parameters.appID.value |= $param1')
    # inject the password
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 $password '. | .parameters.password.value |= $param1')
    # inject the baseUrl (the nested templates will be picked up from here)
    transformedAzureParametersFile=$(echo "${transformedAzureParametersFile}" | jq --raw-output --arg param1 "$baseUrl" '. | .parameters.baseUrl.value |= $param1')

    # create copy of the parameters file for actual deployment
    echo "${transformedAzureParametersFile}" > "${templateDirectory}/test.parameters.json"
}

_createResourceGroup(){
    # uncomment the following if you want to add tags
    #local command="az group create --location ukwest --resource-group ${resourceGroup} --tags OwnerName=${ownerName} Owner=${ownerEmail} InUse=${keepGroupFromReaper}"
    local command="az group create --location ukwest --resource-group ${resourceGroup}"
    local message=""; message=$(echo "Creating the following group"; echo "${command}")
    info "${message}"
    eval "${command}"
}

_deployTheArmTemplate(){
    # kick off the azure deployment
    local command="az group deployment create --template-file ${templateDirectory}/azuredeploy.json --parameters ${templateDirectory}/test.parameters.json --resource-group ${resourceGroup} --no-wait "
    local message=""; message=$(echo "Starting the azure deployment"; echo "${command}")
    info "${message}"
    eval "${command}"
}

main() {
  _createTheDeploymentParameterFile
  _createResourceGroup
  _deployTheArmTemplate
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main
fi

