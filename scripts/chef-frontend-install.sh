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
#/   ./chef-frontend-install.sh --leader \
#/   ...
#/   ...
#/ If this is absent then the server will be treated as a "follower"
#/   ./chef-frontend-install.sh \
#/   ...
#/   ...
#/ For example, the following is an example for a "follower"
#/   ./chef-frontend-install.sh \
#/   --db-password chv-y3nqv5qjny-dbp \
#/   --first-name Gavin \
#/   --last-name Didrichsen \
#/   --email gdidrichsen@chef.io \
#/   --org-name gavinorganization \
#/   --chef-username delivery \
#/   --app-id 52e3d1d9-0f4f-47f5-b6bd-2a5457b55469 \
#/   --tenant-id a2b2d6bc-afe1-4696-9c37-f97a7ac416d7 \
#/   --sp-password 507ed8bf-a5b5-4c54-a210-101a08ae5547 \
#/   --object-id f9842bdf-d3f1-4a31-bd24-cfc9366b35b8 \
#/   --key-vault-name chef-keyy3nqv
#/   --public-dns "my.public.dns.to.the.automate.server"
#/
#/  To debug the script, add the -debug flag before all other flags, e.g.,
#/   ./chef-frontend-install.sh --debug --leader \
#/   --db-password "aaa-2kabc3def4-bbb" \
#/   ...
#/   ...
#/ Options:
#/   --help:                        Display this help message
#/   --debug:                       Triggers trace output on the bash script to help with troubleshooting
#/   --leader:                              Determines whether to treat this server as the one and only one "leader" or a follower
#/   --db-password                      Postgresql database password
#/   --first-name                           First name of the chef server user
#/   --last-name                            Last name of the chef server user
#/   --email                                    Email of the chef server user
#/   --org-name                             Chef server organization name
#/   --chef-username          Chef server user name associated with the organization
#/   --app-id                                   Azure application id
#/   --tenant-id                            Azure tenant id
#/   --sp-password                      Azure service principle password
#/   --object-id                            Azure object id
#/   --key-vault-name                   Azure Key Vault name, the vault in the resource group that holds all the secrets
#/   --public-dns:            The public dns of the automate server
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

# since jq is used to parse arguments, make sure it's installed before proceeding
jqPackage=""; jqPackage=$( (dpkg-query -l jq) || echo "failed")
if [[ "${jqPackage}" == "failed" ]]; then
    info "Installing jq because its required for parsing input arguments"
    apt-get install -y jq
else
    info "jq already installed"
fi

# Define variables that hold the $ENCODED_ARGS that can be passed
# to the script. An existing plain text $ARG_FilE can also be used
ENCODED_ARGS=""
ARG_FILE=""
JSON_SUM_OF_ALL_ARGS="{}"
# initialize variables
CHEF_SERVER_PUBLIC_DNS=""
CHEF_AUTOMATE_PUBLIC_DNS=""
appID=""
chefServerOrganization=""
chefServerUser="delivery"
dbPassword=""
emailId=""
firstName=""
keyVaultName=""
lastName=""
objectId=""
password=""
tenantID=""
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
      -e|--encoded)
      ENCODED_ARGS=$2
      shift 2
      ;;
    -A|--argfile)
      ARG_FILE=$2
      shift 2
      ;;
    -l|--leader)
      thisServerIsTheLeader="true"
      JSON_SUM_OF_ALL_ARGS=$(echo "${JSON_SUM_OF_ALL_ARGS}" | jq --arg param1 "true" '."thisServerIsTheLeader"  |= $param1')
      shift 1
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

# either ARG_FILE or ENCODED_ARGS must be valid; otherwise bomb out
 #if [[ ($ARG_FILE == "" || ! -e $ARG_FILE) && ($ENCODED_ARGS == "") ]]; then
    #error "Either --argfile or --encoded must be set and valid"
    #exit 1
#fi

ARG_FILE="${__dir}/args.json"
# If encoded arguments have been supplied, decode them and save to file
if [ "X${ENCODED_ARGS}" != "X" ]; then
  info "Decoding arguments to ${ARG_FILE}"

  # Decode the bas64 string and write out the ARG file
  echo "${ENCODED_ARGS}" | base64 --decode | jq . > "${ARG_FILE}"
fi

# If the ARG_FILE has been specified and the file exists read in the arguments
if [[ "X${ARG_FILE}" != "X" ]]; then
  if [[ ( -f $ARG_FILE ) ]]; then
    info "$(echo "Reading JSON vars from ${ARG_FILE}:"; cat "${ARG_FILE}" )"

    # combine the --flag arguments with --argsfile values (--flag's will override any values in the --argsfile)
    # and update the $ARG_FILE
    JSON_SUM_OF_ALL_ARGS=$(jq --sort-keys -s '.[0] * .[1]' "${ARG_FILE}" <(echo "${JSON_SUM_OF_ALL_ARGS}"))
    echo "${JSON_SUM_OF_ALL_ARGS}" | jq --sort-keys '.' > "${ARG_FILE}"

    VARS=$(cat "${ARG_FILE}" | jq -r '. | keys[] as $k | "\($k)=\"\(.[$k])\""')
    #info "$(echo "Evaluating the following bash variables:"; echo "${VARS}")"

    # Evaluate all the vars in the arguments
    while read -r line; do
      eval "$line"
    done <<< "$VARS"
  else
    fatal "Unable to find specified args file: ${ARG_FILE}"
  fi
fi

# bomb out if mandatory parameters are not present
if [[ "$appID" == "" ]]; then fatal "appID must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$chefServerOrganization" == "" ]]; then fatal "chefServerOrganization must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$chefServerUser" == "" ]]; then fatal "chefServerUser must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$dbPassword" == "" ]]; then fatal "--bob must be defined"; fi
if [[ "$emailId" == "" ]]; then fatal "emailId must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$firstName" == "" ]]; then fatal "firstName  must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$keyVaultName" == "" ]]; then fatal "keyVaultName must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$lastName" == "" ]]; then fatal "lastName must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$objectId" == "" ]]; then fatal "objectId must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$password" == "" ]]; then fatal "password must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$CHEF_SERVER_PUBLIC_DNS" == "" ]]; then fatal "CHEF_SERVER_PUBLIC_DNS must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$CHEF_AUTOMATE_PUBLIC_DNS" == "" ]]; then fatal "CHEF_AUTOMATE_PUBLIC_DNS must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$tenantID" == "" ]]; then fatal "tenantID must be defined in the ARG_FILE or ENCODED_ARGS"; fi
if [[ "$thisServerIsTheLeader" == "" ]]; then fatal "thisServerIsTheLeader must be defined in the ARG_FILE or ENCODED_ARGS"; fi

# --- Helper scripts end ---

_installPreRequisitePackages() {
    apt-get install -y apt-transport-https
    apt-get install -y sshpass
    apt-get install -y libssl-dev libffi-dev python-dev build-essential
    apt-get install -y jq
}

_installChefFrontendSoftware() {
    local result=""
    (dpkg-query -l chef-server-core && dpkg-query -l chef-manage) || result="failed"
    if [[ "${result}" == "failed" ]]; then
        info "Installing chef-server-core and chef-manage"
        wget -qO - https://downloads.chef.io/packages-chef-io-public.key | sudo apt-key add -
        echo "deb https://packages.chef.io/stable-apt trusty main" > /etc/apt/sources.list.d/chef-stable.list
        apt-get update
        apt-get install -y chef-server-core chef-manage
    else
        info "chef-server-core and chef-manage already installed"
    fi
}

_mountFilesystemForChefFrontend() {
    local result=$(lvdisplay -v chef-vg || echo "not mounted")
    if [[ "${result}" == "not mounted" ]]; then
        info "Mounting the /var/opt/opscode and /var/log/opscode filesystems"
        apt-get install -y lvm2 xfsprogs sysstat atop
        apt-get update
        umount -f /mnt || info "/mnt already umounted"
        pvcreate -f /dev/sdc
        vgcreate chef-vg /dev/sdc
        lvcreate -n chef-data -l 20%VG chef-vg
        lvcreate -n chef-logs -l 80%VG chef-vg
        mkfs.xfs /dev/chef-vg/chef-data
        mkfs.xfs /dev/chef-vg/chef-logs
        mkdir -p /var/opt/opscode
        mkdir -p /var/log/opscode
        mount /dev/chef-vg/chef-data /var/opt/opscode
        mount /dev/chef-vg/chef-logs /var/log/opscode
    else
        info "/var/opt/opscode and /var/log/opscode filesystems already mounted"
    fi
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

_getChefServerConfigText() {
	local result=""
	result=$(cat <<-EOF
		# CHEFSERVER DEFAULT CONFIG START
		fqdn "${fqdn}"
		api_fqdn "${CHEF_SERVER_PUBLIC_DNS}"

		use_chef_backend true
		chef_backend_members ["10.0.1.6", "10.0.1.5", "10.0.1.4"]

		haproxy['remote_postgresql_port'] = 5432
		haproxy['remote_elasticsearch_port'] = 9200

		postgresql['external'] = true
		postgresql['vip'] = '127.0.0.1'
		postgresql['db_superuser'] = 'chef_pgsql'
		postgresql['db_superuser_password'] = '${dbPassword}'

		opscode_solr4['external'] = true
		opscode_solr4['external_url'] = 'http://127.0.0.1:9200'
		opscode_erchef['search_provider'] = 'elasticsearch'
		opscode_erchef['search_queue_mode'] = 'batch'

		bookshelf['storage_type'] = :sql

		rabbitmq['enable'] = false
		rabbitmq['management_enabled'] = false
		rabbitmq['queue_length_monitor_enabled'] = false

		opscode_expander['enable'] = false

		dark_launch['actions'] = false

		opscode_erchef['nginx_bookshelf_caching'] = :on
		opscode_erchef['s3_url_expiry_window_size'] = '50%'
		opscode_erchef['s3_url_expiry_window_size'] = '100%'
		license['nodes'] = 999999
		oc_chef_authz['http_init_count'] = 100
		oc_chef_authz['http_max_count'] = 100
		oc_chef_authz['http_queue_max'] = 200
		oc_bifrost['db_pool_size'] = 20
		oc_bifrost['db_pool_queue_max'] = 40
		oc_bifrost['db_pooler_timeout'] = 2000
		opscode_erchef['depsolver_worker_count'] = 4
		opscode_erchef['depsolver_timeout'] = 20000
		opscode_erchef['db_pool_size'] = 20
		opscode_erchef['db_pool_queue_max'] = 40
		opscode_erchef['db_pooler_timeout'] = 2000
		opscode_erchef['authz_pooler_timeout'] = 2000
		# CHEFSERVER DEFAULT CONFIG END
		EOF
		)
	echo "${result}"
}

_createChefFrontendConfigFile() {
    # only add the CHEFSERVER DEFAULT CONFIG if it isn't already present
    info "checking if the CHEFSERVER DEFAULT CONFIG is set in /etc/opscode/chef-server.rb"
    local result=""; result=$(grep "CHEFSERVER DEFAULT CONFIG" /etc/opscode/chef-server.rb || echo "not present")
    if [[ "${result}" == "not present" ]]; then
        info "creating the CHEFSERVER DEFAULT CONFIG in /etc/opscode/chef-server.rb"
        local result=""
        result=$(_getChefServerConfigText)
        echo "${result}" >  "${DELIVERY_DIR}/chef-server.rb"
    else
        info "CHEFSERVER DEFAULT CONFIG already present in /etc/opscode/chef-server.rb"
    fi
}

_doAChefReconfigure() {
  (
    cd "${DELIVERY_DIR}"
    info "reconfiguring chef-server [chef-server-ctl reconfigure --accept-license]"
    chef-server-ctl reconfigure --accept-license
    info "reconfiguring chef-manage [chef-manage-ctl reconfigure --accept-license]"
    sudo chef-manage-ctl reconfigure --accept-license
  )
}

_enableSystat() {
    echo 'ENABLED="true"' > /etc/default/sysstat
    service sysstat restart
    sleep 5
}

_logonToAzure() {
    local result=''; result=$(az login --service-principal -u "${appID}" --password "${password}" --tenant "${tenantID}")
    if [[ "${result}" == "" ]]; then
        fatal "failed to log into azure"
    else
        info "logged into azure"
    fi
}

_downloadSecretsFromAzureKeyVault() {
    info "downloading private-chef-secrets.json"
    az keyvault secret download --file "${DELIVERY_DIR}/private-chef-secrets.json" --name chefsecrets --vault-name "${keyVaultName}"
    return
}

_uploadSecretsFromAzureKeyVault() {
    info "uploading the secret files to keyvault"
    az keyvault secret set --name chefsecrets --vault-name "${keyVaultName}" --file "${DELIVERY_DIR}/private-chef-secrets.json"
    az keyvault secret set --name chefdeliveryuserkey --vault-name "${keyVaultName}" --file "${DELIVERY_DIR}/${chefServerUser}.pem"
    az keyvault secret set --name cheforganizationkey --vault-name "${keyVaultName}" --file "${DELIVERY_DIR}/${chefServerOrganization}-validator.pem"
    az keyvault secret set --name chefdeliveryuserpassword --vault-name "${keyVaultName}" --value "${password}"
}

_createChefServerUserAndOrg() {
  (
    cd "${DELIVERY_DIR}"

    if [[ ! -e "${DELIVERY_DIR}/${chefServerUser}.pem" ]]; then
      info "creating new chefserver user ${chefServerUser} [${DELIVERY_DIR}/${chefServerUser}.pem]"
      chef-server-ctl user-create "${chefServerUser}" "${firstName}" "${lastName}" "${emailId}" "${password}" --filename "${DELIVERY_DIR}/${chefServerUser}.pem"
      sleep 5
    else
      info "chefserver user already created [${DELIVERY_DIR}/${chefServerUser}.pem]"
    fi

    if [[ ! -e "${DELIVERY_DIR}/${chefServerOrganization}-validator.pem" ]]; then
      info "creating new chefserver organization ${chefServerOrganization} [${DELIVERY_DIR}/${chefServerOrganization}-validator.pem]"
      sudo chef-server-ctl org-create "${chefServerOrganization}" 'Chef Automate Org' --file "${DELIVERY_DIR}/${chefServerOrganization}-validator.pem" -a "${chefServerUser}"
      sleep 5
    else
      info "chefserver organization already created [${DELIVERY_DIR}/${chefServerUser}.pem]"
    fi
  )
}

_createUpgradesFolder() {
    mkdir -p /var/opt/opscode/upgrades/
}

_setBootstrappedFlagToTrue() {
    touch /var/opt/opscode/bootstrapped
}

_getTheAuthenticationToken() {
    # get the automate authentication token if it is available
    local CHEF_AUTOMATE_TOKEN="chefautomatetoken"
    local errorMessage="no token uploaded to key vault"
    local commandToRun=''; commandToRun="az keyvault secret show --name ${CHEF_AUTOMATE_TOKEN} --vault-name ${keyVaultName}"
    info "checking for an existing chefautomate token in the key vault [${commandToRun}]"
    local result=''; result=$(eval "${commandToRun}" || echo "${errorMessage}")

    if [[ "${result}" != "no token uploaded to key vault" ]]; then
        local TOKEN=$(echo "${result}" | jq --raw-output '.value')
        echo "${TOKEN}"
    else
        echo "${errorMessage}"
    fi
}

enableDataForwardingToAutomate() {
	# define the extra config required to wire chefserver to chefautomate
	variable=$(cat <<-EOF

		# DATAFORWARDING CONFIG BLOCK START
		# Configure data collection forwarding from chefserver to chefautomate
		data_collector['root_url'] = 'https://${CHEF_AUTOMATE_PUBLIC_DNS}/data-collector/v0/'
		# Add for chef client run forwarding
		data_collector['proxy'] = true
		# Add for compliance scanning
		profiles['root_url'] = 'https://${CHEF_AUTOMATE_PUBLIC_DNS}'
		# DATAFORWARDING CONFIG BLOCK START
		EOF
		)

    # only add the above DATAFORWARDING CONFIG BLOCK if it isn't already present
    info "checking if the DATAFORWARDING CONFIG BLOCK is set in /etc/opscode/chef-server.rb"
    local dataConfig="not present"; dataConfig=$(grep "DATAFORWARDING CONFIG BLOCK" /etc/opscode/chef-server.rb || echo "not present")
    if [[ "${dataConfig}" == "not present" ]]; then
        # get the automate authentication token if it is available
        local TOKEN='no token uploaded to key vault'; TOKEN=$(_getTheAuthenticationToken)

        # only if an automate token exists in the key vault, then...
        if [[ "${TOKEN}" != "no token uploaded to key vault" ]]; then
            info "setting the authentication token [chef-server-ctl set-secret data_collector token ${TOKEN}]"
            sudo chef-server-ctl set-secret data_collector token "${TOKEN}"

            info "restarting nginx [chef-server-ctl restart nginx]"
            sudo chef-server-ctl restart nginx

            info "restarting opscode-erchef [chef-server-ctl restart opscode-erchef]"
            sudo chef-server-ctl restart opscode-erchef

            info "adding the dataforwarding config to /etc/opscode/chef-server.rb"
            echo "${variable}" >> /etc/opscode/chef-server.rb

            _doAChefReconfigure
        else
            warning "The chefautomate authentication token was not available in key vault"
        fi

  else
        info "DATAFORWARDING CONFIG BLOCK already present in /etc/opscode/chef-server.rb"
  fi

}

DELIVERY_DIR="/etc/opscode"
mkdir -p "${DELIVERY_DIR}"
fqdn=$(hostname -f)
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    trap cleanup EXIT
    _installPreRequisitePackages
    _installChefFrontendSoftware
    _mountFilesystemForChefFrontend
    _installAzureCli
    _logonToAzure
    _createChefFrontendConfigFile

    if [[ "${thisServerIsTheLeader}" == "true" ]]; then
        _doAChefReconfigure
        # NOW set the secret token and restart nginx
        # NOW add the extra data-forwarder config
        # NOW do 'sudo chef-server-ctl reconfigure'
        enableDataForwardingToAutomate
        _enableSystat
        _createChefServerUserAndOrg
        _uploadSecretsFromAzureKeyVault
    else
        _downloadSecretsFromAzureKeyVault
        _createUpgradesFolder
        _setBootstrappedFlagToTrue
        _doAChefReconfigure
        # NOW set the secret token and restart nginx
        # NOW add the extra data-forwarder config
        # NOW do 'sudo chef-server-ctl reconfigure'
        enableDataForwardingToAutomate
        _enableSystat
    fi
fi

