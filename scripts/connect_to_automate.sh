#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# --- Helper scripts start ---

#/
#/ Usage:
#/ Description:
#/ Examples:
#/   ...
#/ Options:
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
trap cleanup EXIT

_setupAutomateTokenOnChefServer() {
	info "setting the authentication token"
	sudo chef-server-ctl set-secret data_collector token "${TOK}"
}

_restartServices() {
	info "restarting nginx [chef-server-ctl restart nginx]"
	sudo chef-server-ctl restart nginx
	info "restarting opscode-erchef [chef-server-ctl restart opscode-erchef]"
	sudo chef-server-ctl restart opscode-erchef
}

enableDataForwardingToAutomate() {
	variable=$(cat <<-EOF

		# DATAFORWARDING CONFIG BLOCK START
		# Configure data collection forwarding from chefserver to chefautomate
		data_collector['root_url'] = 'https://${AUTOMATE_URL}/data-collector/v0/'
		# Add for chef client run forwarding
		data_collector['proxy'] = true
		# Add for compliance scanning
		profiles['root_url'] = 'https://${AUTOMATE_URL}'
		# DATAFORWARDING CONFIG BLOCK START
		EOF
		)

  local result=""; result=$(grep "DATAFORWARDING CONFIG BLOCK" /etc/opscode/chef-server.rb || echo "not present")
  if [[ "${result}" == "not present" ]]; then
		_setupAutomateTokenOnChefServer
		_restartServices

    info "adding the dataforwarding config to /etc/opscode/chef-server.rb"
    echo "${variable}" >> /etc/opscode/chef-server.rb
		info "reconfiguring chef-server [chef-server-ctl reconfigure]"	
		sudo chef-server-ctl reconfigure
  else
    info "already present"
  fi
  
}

TOK="n2YzvvYu5JQMM9hZlXc_NMfVlmA="
AUTOMATE_URL="chefautomateqcc.ukwest.cloudapp.azure.com"

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
	enableDataForwardingToAutomate
fi
