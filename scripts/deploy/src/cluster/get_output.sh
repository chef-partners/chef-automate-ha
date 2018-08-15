#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts begin ---
#/ Usage:
#/ Description: Gets all necessary values required to configure automate and create necessary test nodes
#/ Examples:
#/  ./summarizeOutputs.sh \
#/    --password "507ed8bf-a5b5-4c54-a210-101a08ae5547" \
#/    --app-id "52e3d1d9-0f4f-47f5-b6bd-2a5457b55469" \
#/    --tenant-id "a2b2d6bc-afe1-4696-9c37-f97a7ac416d7" \
#/    --resource-group "gdResourceGroup"
#/    --output-dir "${PwD}"
#/ Options:
#/   --help: Display this help message
#/   --debug: Add extra debug to the output
#/   --password: Azure Service Princiipal password
#/   --app-id: Azure Service Principal app-id
#/   --tenant-id: Azure tenant-id
#/   --resource-group: Resource Group for the azure deployment
#/   --output-dir: The directory to which you want the output delivered
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

: '
Log info(), warning(), error() from a subshell so that this
can be used within functions that return output.  In other words
the subshell ensures that the info,warning,error message does not dirty
the function output, the "echo"
'
readonly LOG_FILE="/tmp/$(basename "$0").log"
readonly DATE_FORMAT="+%Y-%m-%d_%H:%M:%S.%2N"
info()    { ( echo "[$(date ${DATE_FORMAT})] [INFO]    $*" | tee -a "$LOG_FILE" >&2 ; ) }
warning() { ( echo "[$(date ${DATE_FORMAT})] [WARNING] $*" | tee -a "$LOG_FILE" >&2 ; ) }
error()   { ( echo "[$(date ${DATE_FORMAT})] [ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; ) }
fatal()   { echo "[$(date ${DATE_FORMAT})] [FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; kill 0 ; }

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
trap "kill 0" SIGINT
trap cleanup EXIT

# initialize flag variables
ARG_FILE="${__dir}/input/args.json"
resourceGroup=""
outputDirectory="${__dir}/output"
# initialize JSON variables picked up from the --argfile
adminUsername=""
appID=""
baseUrl=""
objectId=""
organizationName=""
ownerEmail=""
ownerName=""
password=""
tenantID=""
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
    -r|--resource-group)
      resourceGroup=$2
      shift 2
      ;;
    -o|--output-dir)
      outputDirectory=$2
      shift 2
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
      error "Error: Unsupported flag $1"
      usage
      exit 1
      ;;
    *) # preserve positional arguments
      warning "Ignoring script parameter ${1} because no valid flag preceeds it"
      shift
      ;;
  esac
done

# If the ARG_FILE has been specified and the file exists read in the arguments
if [[ "X${ARG_FILE}" != "X" ]]; then
  if [[ ( -f $ARG_FILE ) ]]; then
    info "$(echo "Reading JSON vars from ${ARG_FILE}:"; cat "${ARG_FILE}" )"
    VARS=$(cat ${ARG_FILE} | jq -r '. | keys[] as $k | "\($k)=\"\(.[$k])\""')

    # Evaluate all the vars in the arguments
    while read -r line; do
      eval "$line"
    done <<< "$VARS"
  else
    fatal "Unable to find specified args file: ${ARG_FILE}"
  fi
fi

# fail if mandetory flags aren't set
if [[ "$resourceGroup" == "" ]]; then fatal "--resource-group flag must be defined"; fi
if [[ "${ARG_FILE}" == "" && ( ! -e "${ARG_FILE}")]]; then fatal "--argfile flag must be defined with a valid json argument file [${ARG_FILE}]"; fi
# fail of mandetory JSON fields in the --argfile aren't set
if [[ "$appID" == "" ]]; then fatal "appID must be defined in the args.json"; fi
if [[ "$password" == "" ]]; then fatal "password must be defined in the args.json"; fi
if [[ "$tenantID" == "" ]]; then fatal "tenantID must be defined in the args.json"; fi
if [[ "$organizationName" == "" ]]; then fatal "organizationName must be defined in the args.json"; fi

# --- Helper scripts end ---

_logonToAzure() {
      local result=''; result=$(az login --service-principal -u "${appID}" --password "${password}" --tenant "${tenantID}")
    if [[ "${result}" == "" ]]; then
      fatal "failed to log into azure"
    else
      info "logged into azure"
    fi
}

_getDeploymentStatus() {
    local result=""
    result=$(az group deployment show --resource-group "${resourceGroup}" --name azuredeploy --query properties | jq --raw-output '.provisioningState')

    # bomb out if status comes back ""
    if [[ "${result}" == "" ]]; then
      fatal "deployment status has come back empty; make sure that the deployment has been started before proceeding."
    fi

    (
      info "deployment status for ${resourceGroup} is ${result}"
    )
    echo "${result}"
}

_bombOutIfDeplomentStatusIsNotSuccessful() {
    local statusOfDeployment=$(_getDeploymentStatus)

    if [[ "$statusOfDeployment" == "Failed" ]]; then
      fatal "The deployment to ${resourceGroup} failed"
    fi

    if [[ "$statusOfDeployment" == "Running" ]]; then
      fatal "The deployment to ${resourceGroup} is in progress; try again later"
    fi

    if [[ "${statusOfDeployment}" == "Succeeded" ]]; then
      info "The deployment to ${resourceGroup} succeeded"
    fi
}

: '
Get the raw outputs json from azure, something like:
{
    "adminusername": {
      "type": "String",
      "value": "azureuser"
    },
    "chefAutomateFqdn": {
      "type": "String",
      "value": "chefautomateikd.ukwest.cloudapp.azure.com"
    },
    "chefAutomatePassword": {
      "type": "String",
      "value": "The chefAutomatePassword is stored in the keyvault, you can retrieve it using azure CLI 2.0 [az keyvault secret show --name chefautomateuserpassword --vault-name < keyvaultname >]"
    },
...
...
and transform it into something like this:
{
  "adminusername": "azureuser",
  "chefAutomateFqdn": "chefautomateikd.ukwest.cloudapp.azure.com",
  "chefAutomatePassword": "The chefAutomatePassword is stored in the keyvault, you can retrieve it using azure CLI 2.0 [az keyvault secret show --name chefautomateuserpassword --vault-name < keyvaultname >]",
...
...
'
_getRawDeploymentOutputs(){
    # get the raw deployment outputs
    local result=""
    result=$(az group deployment show --resource-group "${resourceGroup}" --name azuredeploy --query properties.outputs | jq --raw-output '.')

    # bomb out if the outputs are empty...they shouldn't be
    if [[ "${result}" == "" ]]; then fatal "The outputs for ${resourceGroup} are empty.  Check the deployment for errors"; fi

    # reformat the raw output
    result=$(echo "${result}" | jq --sort-keys 'with_entries(.value |= .value)')
    info "raw outputs from azure deployment: ${result}"

    echo "${result}"
}

_bombOutIfDeplomentStatusIsNotSuccessful() {
    local statusOfDeployment=$(_getDeploymentStatus)

    if [[ "$statusOfDeployment" == "Failed" ]]; then
      fatal "The deployment to ${resourceGroup} failed"
    fi

    if [[ "$statusOfDeployment" == "Running" ]]; then
      fatal "The deployment to ${resourceGroup} is in progress; try again later"
    fi

    if [[ "${statusOfDeployment}" == "Succeeded" ]]; then
      info "The deployment to ${resourceGroup} succeeded"
    fi
}

_enhanceDeploymentOutputs(){
    # transform the raw "ouputs" JSON from azure
    local result=$(_getRawDeploymentOutputs)

    # get the key vault name
    local keyVaultName=$(echo "${result}" | jq --raw-output '.keyvaultName')

    # get the chef automate password
    local chefAutomatePassword=$(az keyvault secret show --name chefautomateuserpassword --vault-name "${keyVaultName}" | jq --raw-output '.value')
    result=$(echo "${result}" | jq --arg param1 "${chefAutomatePassword}" '."chefAutomatePassword" |= $param1')

    # get the chef server password
    local chefServerPassword=$(az keyvault secret show --name chefdeliveryuserpassword --vault-name "${keyVaultName}" | jq --raw-output '.value')
    result=$(echo "${result}" | jq --arg param1 "${chefServerPassword}" '."chefServerWebLoginPassword"  |= $param1')

    # add the azureResourceGroupForChefServer
    result=$(echo "${result}" | jq --arg param1 "${resourceGroup}" '."azureResourceGroupForChefServer"  |= $param1')

    # combine the --argsfile input JSON with the outputs from the deployment
    result=$(jq --sort-keys -s '.[0] * .[1]' "${ARG_FILE}" <(echo "${result}"))

    # sort the json keys
    result=$(echo "${result}" | jq --sort-keys '.')

    # log from a subshell so not to dirty the output from this function
    (
      info "transformed outputs from azure deployment:${result}"
    )
    echo "${result}"
}

_writeTheDeploymentOutputSummary(){
    # write out the enhanced output
    local resultEnhanced=$(_enhanceDeploymentOutputs)
    info "writing the outputs summary to ${outputFileEnhanced}"
    echo "${resultEnhanced}" > "${outputFileEnhanced}"
}

_downloadSecretsFromAzureKeyVault() {
    local chefServerUserPrivateKey="delivery.pem"
    local chefServerOrganizationValidatorPrivateKey="${organizationName}-validator.pem"

    info "Downloading chefserver private keys: ${chefServerUserPrivateKey} and ${chefServerOrganizationValidatorPrivateKey} to ${outputDirectory}"
    local keyVaultName=$(cat "${outputFileEnhanced}" | jq --raw-output '.keyvaultName')
    az keyvault secret download --file "${outputDirectory}/${chefServerUserPrivateKey}" --name chefdeliveryuserkey --vault-name "${keyVaultName}"
    az keyvault secret download --file "${outputDirectory}/${chefServerOrganizationValidatorPrivateKey}" --name cheforganizationkey --vault-name "${keyVaultName}"
    return
}

# ensure the $outputDirectory exists
rm -rf "${outputDirectory}" || info "output directory already deleted"
mkdir -p "${outputDirectory}"
outputFileEnhanced="${outputDirectory}/args.json"

main() {
    _logonToAzure
    _bombOutIfDeplomentStatusIsNotSuccessful

    # otherwise...
    _writeTheDeploymentOutputSummary
    _downloadSecretsFromAzureKeyVault
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main
fi

