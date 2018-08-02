#!/bin/bash

: '
Get the current script directory
'
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__srcDir=${__dir/\/test\//\/src\/}

: '
Create a new parameters file test.parameters.json, a copy of the azuredeploy.parameters.json,
injecting all necessary parameters defined in the args.json file
'
"${__srcDir}"/get_output.sh --resource-group "gdResourceGroupClient30" \

