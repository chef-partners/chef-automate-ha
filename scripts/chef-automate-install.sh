#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts start ---

#/
#/ Usage:
#/ Description: Install and Deploy Chef Automate
#/ Examples:
#/   ./chef-automate-install.sh --app-id "52e3d1d9-0g5g-47f5-b6bd-2a5457b55469" \
#/   --tenant-id "a2b2d6bc-bgf2-4696-9c37-g98a7ac416d7" \
#/   --password "507ed8bf-z7j8-4c54-b321-101a08ae5547" \
#/   --key-vault-name "chef-keya1mbw"
#/  To debug the script process and values, add the -debug flag before all other flags, e.g.,
#/   ./chef-automate-install.sh --debug --app-id "52e3d1d9-0g5g-47f5-b6bd-2a5457b55469" ...
#/ Options:
#/   --help:           Display this help message
#/   --debug:          Triggers trace output on the bash script to help with troubleshooting
#/   --app-id:         Azure Service Principle Application ID
#/   --tenant-it:      Azure Tenant ID
#/   --password:       Azure Service Principle Password
#/   --key-vault-name: Name of the aure key vault owned by Azure Service Principle storing all the secrets
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

# Run these at the start and end of every script ALWAYS
info "Starting ${__file}"
cleanup() {
		local result=$? 
		if (( result  > 0 )); then
				error "Exiting ${__file} prematurely with exit code [${result}]"
		else
				info "Exiting ${__file} cleanly with exit code [${result}]"
		fi
}

# initialize variables
appID=""
tenantID=""
password=""
objectId=""
keyVaultName=""
publicDnsOfServer=""
while (( "$#" )); do
  case "$1" in
    -d|--debug)
      set -o xtrace
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    -a|--app-id)
      appID=$2
      shift 2
      ;;
    -t|--tenant-id)
      tenantID=$2
      shift 2
      ;;
    -p|--password)
      password=$2
      shift 2
      ;;
    -k|--key-vault-name)
      keyVaultName=$2
      shift 2
      ;;
    -o|--object-id)
      objectId=$2
      shift 2
      ;;
    -x|--public-dns)
      publicDnsOfServer=$2
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


# --- Helper scripts end ---

_installPreRequisitePackages(){
	local result=""
	(dpkg-query -l libssl-dev && dpkg-query -l libffi-dev && dpkg-query -l python-dev &&  dpkg-query -l build-essential) || result="failed"
	if [[ "${result}" == "failed" ]]; then
		info "Installing pre-requisite packages"
		apt-get install -y libssl-dev libffi-dev python-dev build-essential
	else
		info "pre-requsite packages installed"
	fi
	return
}

_installAzureCli() {
	local result=""
	(dpkg-query -l azure-cli ) || result="failed"
	if [[ "${result}" == "failed" ]]; then
		info "Installing azure-cli"
		AZ_REPO=$(lsb_release -cs)
		echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
		curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
		apt-get update
		apt-get install -y azure-cli
	else
		info "azure-cli already installed"
	fi
	return
}

_downloadSecretsFromAzureKeyVault() {
	az login --service-principal -u "${appID}" --password "${password}" --tenant "${tenantID}"
	az keyvault secret download --file "${DELIVERY_DIR}/chefautomatedeliveryuser.pem" --name chefdeliveryuserkey --vault-name "${keyVaultName}"
	return
}

_downloadAutomateV2() {
	(
	cd "${DELIVERY_DIR}"
	if [[ ! -e "chef-automate" ]]; then
		info "Downloading Automate V2"
		curl https://packages.chef.io/files/current/latest/chef-automate-cli/chef-automate_linux_amd64.zip | gunzip - > chef-automate && chmod +x chef-automate
	else
		info "Automate V2 already downloaded"
	fi
	)
}

_initializeAutomateV2() {
	(
	cd "${DELIVERY_DIR}"
	if [[ ! -e "config.toml" ]]; then
		info "Initializing Automate V2"
		local publicFqdnEntry="  fqdn = \"${publicDnsOfServer}\""
		./chef-automate init-config
		cp config.toml config-public.toml
		sed -i '/fqdn =/c\'"${publicFqdnEntry}" config-public.toml
	else
		info "Automate V2 already initialized"
	fi
	)
}

: '
Make transient sysctl changes and lock-in after reboot by writing to /etc/sysctl.d
'
_setValidKernelAttributes() {
	VM_MAX_MAP_COUNT=$(sysctl vm.max_map_count | awk '{print $3}')
	VM_MAX_MAP_COUNT_EXPECTED=262144
	if (( VM_MAX_MAP_COUNT != VM_MAX_MAP_COUNT_EXPECTED )); then
		info "Configuring the kernel vm.max_map_count [${VM_MAX_MAP_COUNT}] to be ${VM_MAX_MAP_COUNT_EXPECTED}"
		sysctl -w vm.max_map_count=${VM_MAX_MAP_COUNT_EXPECTED}
		echo "vm.max_map_count=${VM_MAX_MAP_COUNT_EXPECTED}" > /etc/sysctl.d/50-chef-automate.conf
	else
		info "Kernal vm.max_map_count [${VM_MAX_MAP_COUNT}] already valid"
	fi

	VM_DIRTY_EXPIRE_CENTISECS=$(sysctl vm.dirty_expire_centisecs | awk '{print $3}')
	VM_DIRTY_EXPIRE_CENTISECS_EXPECTED=20000
	if (( VM_DIRTY_EXPIRE_CENTISECS != VM_DIRTY_EXPIRE_CENTISECS_EXPECTED )); then
		info "Configuring the kernel vm.dirty_expire_centisecs [${VM_DIRTY_EXPIRE_CENTISECS}] to be ${VM_DIRTY_EXPIRE_CENTISECS_EXPECTED}"
		sysctl -w vm.dirty_expire_centisecs=${VM_DIRTY_EXPIRE_CENTISECS_EXPECTED}
		echo "vm.dirty_expire_centisecs=${VM_DIRTY_EXPIRE_CENTISECS_EXPECTED}" >> /etc/sysctl.d/51-chef-automate.conf
	else
		info "Kernel vm.dirty_expire_centisecs [${VM_DIRTY_EXPIRE_CENTISECS}] already valid"
	fi
}

_deployAutomateV2() {
	(
	cd "${DELIVERY_DIR}"
	if [[ ! -e "automate-credentials.toml" ]]; then
		info "Deploying Automate V2"
		export GRPC_GO_LOG_SEVERITY_LEVEL=info GRPC_GO_LOG_VERBOSITY_LEVEL=2
		./chef-automate deploy config-public.toml --accept-terms-and-mlsa --debug
	else
		info "Automate V2 already deployed"
	fi
	)
}

_uploadChefAutomatePasswordToAzureKeyVault() {
	(
		info "Uploading automate credentials to key vault"
		cd "${DELIVERY_DIR}"
		az login --service-principal -u "${appID}" --password "${password}" --tenant "${tenantID}"
		local automatePassword=$( cat automate-credentials.toml | perl -ne 'print "$1\n" if /password = "(.*?)"/' 2>/dev/null )
		az keyvault secret set --name chefautomateuserpassword --vault-name "${keyVaultName}" --value "${automatePassword}"
	)
	return
}

DELIVERY_DIR="/etc/delivery"
mkdir -p "${DELIVERY_DIR}"
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
	trap cleanup EXIT
	_installPreRequisitePackages
	_setValidKernelAttributes
	_installAzureCli
	_downloadSecretsFromAzureKeyVault
	_downloadAutomateV2
	_initializeAutomateV2
	_deployAutomateV2
	_uploadChefAutomatePasswordToAzureKeyVault
fi
