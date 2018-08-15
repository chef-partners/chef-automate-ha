#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts start ---

#/
#/ Usage:
#/ Description: Install and Deploy Chef Backend Software Packages
#/ Examples:
#/ For the "leader" server, you must send the "--leader" flag;
#/   ./chef-backend-install.sh --leader \
#/   ...
#/   ...
#/ If this is absent then the server will be treated as a "follower"
#/   ./chef-backend-install.sh \
#/   ...
#/   ...
#/ For example, the following is an example for a "follower"
#/   ./chef-backend-install.sh \
#/   --db-password "aaa-2kabc3def4-bbb" \
#/   --replication-password "ccc-2kabc3def4-ddd" \
#/   --cluster-token "eee-2kabc3def4-fff" \
#/   --cluster-name "chef-keya1mbw"
#/
#/  To debug the script, add the -debug flag before all other flags, e.g.,
#/   ./chef-backend-install.sh --debug --leader \
#/   --db-password "aaa-2kabc3def4-bbb" \
#/   ...
#/   ...
#/ Options:
#/   --help:                        Display this help message
#/   --debug:                       Triggers trace output on the bash script to help with troubleshooting
#/   --db-password:             Postgresql db_superuser_password
#/   --replication-password:    Postgresql replication_password
#/   --cluster-token:           etcd inital_cluster_token
#/   --cluster-name:                    Elasticsearch cluster_name
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
dbPassword=""
replicationPassword=""
clusterToken=""
clusterName=""
thisServerIsTheLeader="false"
while (( "$#" )); do
  case "$1" in
    -d|--debug)
      set -o xtrace
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    -l|--leader)
      thisServerIsTheLeader="true"
      shift 1
      ;;
    -p|--db-password)
      dbPassword=$2
      shift 2
      ;;
    -r|--replication-password)
      replicationPassword=$2
      shift 2
      ;;
    -t|--cluster-token)
      clusterToken=$2
      shift 2
      ;;
    -n|--cluster-name)
      clusterName=$2
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

_installPreRequisitePackages() {
    apt-get install -y apt-transport-https
    apt-get install -y jq
}

_installChefBackendSoftware() {
    local result=""
    (dpkg-query -l chef-backend) || result="failed"
    if [[ "${result}" == "failed" ]]; then
        info "Installing chef-backend"
        wget -qO - https://downloads.chef.io/packages-chef-io-public.key | sudo apt-key add -
        echo "deb https://packages.chef.io/stable-apt trusty main" > /etc/apt/sources.list.d/chef-stable.list
        apt-get update
        apt-get install -y chef-backend
    else
        info "chef-backend already installed"
    fi
}

_mountFilesystemForChefBackend() {
    if [[ ! -e "/var/opt/chef-backend" ]]; then
        info "Mounting the /var/opt/chef-backend filesystem"
        apt-get install -y lvm2 xfsprogs sysstat atop
        umount -f /mnt
        pvcreate -f /dev/sdc
        vgcreate chef-vg /dev/sdc
        lvcreate -n chef-lv -l 80%VG chef-vg
        mkfs.xfs /dev/chef-vg/chef-lv
        mkdir -p /var/opt/chef-backend
        mount /dev/chef-vg/chef-lv /var/opt/chef-backend
    else
        info "/var/opt/chef-backend filesystem already mounted"
    fi
}

_createBackendSecretsConfigFile() {
  info "Creating the chef-backend-secrets.json"
	cat > "${DELIVERY_DIR}/chef-backend-secrets.json" <<-EOF
		{
		"postgresql": {
		"db_superuser_password": "######",
		"replication_password": "#######"
		},
		"etcd": {
		"initial_cluster_token": "########"
		},
		"elasticsearch": {
		"cluster_name": "#########"
		}
		}
		EOF

	sed -i '0,/######/s//'$dbPassword'/' "${DELIVERY_DIR}/chef-backend-secrets.json"
	sed -i '0,/#######/s//'$replicationPassword'/' "${DELIVERY_DIR}/chef-backend-secrets.json"
	sed -i '0,/########/s//'$clusterToken'/' "${DELIVERY_DIR}/chef-backend-secrets.json"
	sed -i '0,/#########/s//'$clusterName'/' "${DELIVERY_DIR}/chef-backend-secrets.json"
}

_createBackendNetworkConfigFile() {
	info "Creating chef-backend.rb network config file"
	IP=$( ifconfig eth0 | awk '/inet addr/{print substr($2,6)}' )
	cat > "${DELIVERY_DIR}/chef-backend.rb" <<-EOF
		publish_address '${IP}'
		postgresql.log_min_duration_statement = 500
		elasticsearch.heap_size = 3500
		postgresql.md5_auth_cidr_addresses = ["samehost", "samenet", "10.0.0.0/24"]
		EOF
}

_setupTheChefBackendLeader() {
    (
        local result=""
        ( chef-backend-ctl cluster-status --json ) || result="cluster not configured"
        if [[ "${result}" == "cluster not configured" ]]; then
            info "Setting up the backend cluster leader"
            cd "${DELIVERY_DIR}"
            chef-backend-ctl create-cluster --accept-license --yes --quiet --verbose
        else
            info "Backend cluster leader already setup"
        fi
    )
}

_setupTheChefBackendFollower() {
    (
        local result=""
        ( chef-backend-ctl cluster-status --json ) || result="cluster not configured"
        if [[ "${result}" == "cluster not configured" ]]; then
            info "Joining backend follower to the cluster"
            cd "${DELIVERY_DIR}"
            chef-backend-ctl join-cluster 10.0.1.4 -s "${DELIVERY_DIR}/chef-backend-secrets.json" --accept-license --yes --quiet --verbose
        else
            info "Backend follower already joined to the cluster"
        fi
    )
}

DELIVERY_DIR="/etc/chef-backend"
mkdir -p "${DELIVERY_DIR}"
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    trap cleanup EXIT
    _installPreRequisitePackages
    _installChefBackendSoftware
    _mountFilesystemForChefBackend
    _createBackendSecretsConfigFile
    _createBackendNetworkConfigFile

    if [[ "${thisServerIsTheLeader}" == "true" ]]; then
        _setupTheChefBackendLeader
    else
        _setupTheChefBackendFollower
    fi
fi
