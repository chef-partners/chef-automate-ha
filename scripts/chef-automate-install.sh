#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts start ---

#/ Usage:
#/ Description:
#/ Examples:
#/   ./chef-automate-install.sh --debug --app-id "52e3d1d9-0g5g-47f5-b6bd-2a5457b55469" --tenant-id "a2b2d6bc-bgf2-4696-9c37-g98a7ac416d7" --password "507ed8bf-z7j8-4c54-b321-101a08ae5547" --key-vault-name "chef-keya1mbw"
#/ Options:
#/   --help: Display this help message
#/   --debug: Triggers trace output on the bash script to help with troubleshooting
#/   --app-id: Application ID
#/   --tenant-it: Tenant ID
#/   --password: Password
#/   --key-vault-name: Name of the aure key vault that stores all the secrets
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

# initialize variables
appID=""
tenantID=""
password=""
objectId=""
keyVaultName=""
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
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# set positional arguments in their proper place
eval set -- "$PARAMS"

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename "${__file}" .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this as it depends on your app

# Setup logging
readonly LOG_FILE="/tmp/$(basename "$0").log"
readonly DATE_FORMAT="+%Y-%m-%d_%H:%M:%S.%2N"
info()    { echo "[$(date ${DATE_FORMAT})] [INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[$(date ${DATE_FORMAT})] [WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[$(date ${DATE_FORMAT})] [ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[$(date ${DATE_FORMAT})] [FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

# --- Helper scripts end ---

_downloadSecretsFromAzureKeyVault() {
	apt-get install -y libssl-dev libffi-dev python-dev build-essential
	AZ_REPO=$(lsb_release -cs)
	echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
	curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
	apt-get update
	apt-get install -y azure-cli
	apt-get install -y apt-transport-https
	apt-get update
	apt-get install -y sshpass
	apt-get install -y wget
	apt-get install -y lvm2 xfsprogs sysstat atop

	az login --service-principal -u "${appID}" --password "${password}" --tenant "${tenantID}"
	az keyvault secret download --file "${DELIVERY_DIR}/chefautomatedeliveryuser.pem" --name chefdeliveryuserkey --vault-name "${keyVaultName}"
    return
}

: '
NOTE: Not sure that we need this anymore.
Keeping it just in case AND commenting out
the reference to it in the main method
'
_createVarOptDeliveryMount() {
	if [[ ! -e "/var/opt/delivery" ]]; then
		info "/var/opt/delivery to be mounted"
		umount -f /mnt
		pvcreate -f /dev/sdc
		vgcreate delivery-vg /dev/sdc
		lvcreate -n delivery-lv -l 80%VG delivery-vg
		mkfs.xfs /dev/delivery-vg/delivery-lv
		mkdir -p /var/opt/delivery
		mount /dev/delivery-vg/delivery-lv /var/opt/delivery
	else
		info "/var/opt/delivery already mounted"
	fi

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
		./chef-automate init-config
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

function _deployAutomateV2() {
	(
	cd "${DELIVERY_DIR}"
	if [[ ! -e "automate-credentials.toml" ]]; then
		info "Deploying Automate V2"
		export GRPC_GO_LOG_SEVERITY_LEVEL=info GRPC_GO_LOG_VERBOSITY_LEVEL=2
		./chef-automate deploy config.toml --accept-terms-and-mlsa --debug
	else
		info "Automate V2 already deployed"
	fi
	)
}

DELIVERY_DIR="/etc/delivery"
mkdir -p "${DELIVERY_DIR}"
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
	#_createVarOptDeliveryMount
	_setValidKernelAttributes
  _downloadSecretsFromAzureKeyVault
	_downloadAutomateV2
	_initializeAutomateV2
	_deployAutomateV2
fi











