#!/bin/bash

: '
Get the current script directory
'
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: '
Create a new parameters file test.parameters.json, a copy of the azuredeploy.parameters.json,
injecting all necessary parameters defined in the args.json file
'
./deploy_clients.sh \
	--template-directory "${__dir}/deploy_clients/arm" \
	--resource-group "gdResourceGroupClient30" \
	--argfile "${__dir}/deploy_cluster/args.json"

