#!/bin/bash

: '
Get the current script directory
'
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__srcDir=${__dir/\/test\//\/src\/}
__root="$(echo "${__dir}" | sed 's/chef-automate-ha.*/chef-automate-ha/')"

: '
Create a new parameters file test.parameters.json, a copy of the azuredeploy.parameters.json,
injecting all necessary parameters defined in the args.json file
'
"${__srcDir}"/deploy.sh \
	--template-directory "${__root}" \
	--resource-group "gdResourceGroupAutomateDUMPME" \
	--argfile "${__srcDir}/input/args.json"

