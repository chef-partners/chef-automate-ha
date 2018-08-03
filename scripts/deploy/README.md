
# How to deploy cluster and sample clients

## Overview of the process

In order to begin using the chef automate cluster, to wire in clients, for example, there are a number of high level features that should be understood first:

Deploying the chef-automate-ha cluster

- (1) Deploy the chef-automate-ha cluster.  During the deployment all restricted information like credentials and private keys are stored in a key vault.  Other information like the chefserver username and public DNS are published at the end of a successful deployment in the outputs section of the deployment summary JSON.
- (2a) Log onto azure after a successful deployment of the cluster and get all required infomation:  Query the Key Vault for the credentials and private keys.  Query the azure resource group, in which the cluster is deployed, to get all deployment outputs. 
- (2b) Store locally all the credentials, private keys, and output information.  All of these will be required for the next stage, wiring in client nodes.

![overview diagram part 1](img/overview1.png)

Wiring in client nodes:

- (3) Deploy the client(s) to a different azure resource group.
- (4a) Initialize knife so that it can query the chefserver regarding client nodes, upload cookbooks.
- (4b) Use knife to bootstrap the client(s).

![overview diagram part 2](img/overview_2.png)

## Overview of the directory structure

```bash
.
├── azuredeploy.json
├── azuredeploy.parameters.json
├── nested
└── scripts
    └── deploy
        ├── README.md
        ├── src
        │   ├── clients
        │   │   ├── arm
        │   │   │   ├── azuredeploy.json
        │   │   │   ├── azuredeploy.parameters.json
        │   │   │   └── metadata.json
        │   │   ├── deploy.sh
        │   │   └── get_output.sh
        │   ├── cluster
        │   │   ├── deploy.sh
        │   │   ├── get_output.sh
        │   │   └── input
        │   │       └── args.json.sample
        │   └── knife
        │       ├── connectClientsToChefServer.sh
        │       └── cookiecutter-knife
        │           ├── cookiecutter.json.template
        │           └── {{cookiecutter.dir_name}}
        │               ├── .chef
        │               │   └── knife.rb
        │               ├── cookbooks
        │               │   └── starter
        │               ├── doKnifeBootstrap.sh
        │               └── test_doKnifeBootstrap.sh
        └── test
            ├── clients
            │   ├── deploy_test.sh
            │   └── get_output_test.sh
            └── cluster
                ├── deploy_test.sh
                └── get_output_test.sh

23 directories, 51 files

```

## Get the summary of the cluster deployment

Setup the initial JSON file with required inputs:

```bash
cd ./cluster/input
cp args.json.sample args.json
```

Edit the args.json file noting:
- baseUrl is the url for the chef-automate-ha repository. (The link below is correct for now as this code is temporarily on a branch)
- appID, objectId, password, and tennantID are all the values obtain from your existing service principal or the one you created earlier.
- ownerEmail and ownerName are used to tag the azure resource group

```json
{
  "adminUsername": "azureuser",
  "appID": "52e3d1d9-xxxx-yyyy-zzzz-2a5447b55469",
  "baseUrl": "https://raw.githubusercontent.com/chef-partners/chef-automate-ha/add_test_nodes_dev/",
  "objectId": "f9842bdf-xxxx-yyyy-zzzz-cfc8366b35b8",
  "organizationName": "chefserverorganization",
  "ownerEmail": "bob@company.com",
  "ownerName": "bob",
  "password": "508ed8bf-xxxx-yyyy-zzzz-101a08ae5547",
  "tenantID": "a2b2d7bc-xxxx-yyyy-zzzz-f98a7ac416d7"
}
```

Deploy the cluster:






- Get all the required outputs from the cluster deployment

```bash

```

- Tree the output of the summarize_cluster directory.

```bash

'''
