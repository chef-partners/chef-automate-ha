


## Get the summary of the cluster deployment

- Get all the required outputs from the cluster deployment

```bash
➜  deploy git:(add_test_nodes_dev) ./summarize_cluster.sh --resource-group gdResourceGroupAutomate20 --argfile deploy_cluster/args.json
[2018-08-01_10:08:58.2N] [INFO]    Executing /Users/gavindidrichsen/Documents/@REFERENCE/azure/scripts/arm/chef-automate-ha/scripts/deploy/summarize_cluster.sh
[2018-08-01_10:08:58.2N] [INFO]    Reading JSON vars from deploy_cluster/args.json:
{
  "adminUsername": "azureuser",
  "appID": "52e3d1d9-0f4f-47f5-b6bd-2a5457b55469",
  "baseUrl": "https://raw.githubusercontent.com/chef-partners/chef-automate-ha/add_test_nodes_dev/",
  "objectId": "f9842bdf-d3f1-4a31-bd24-cfc9366b35b8",
  "organizationName": "gavinorganization",
  "ownerEmail": "gdidrichsen@chef.io",
  "ownerName": "gavin",
  "password": "507ed8bf-a5b5-4c54-a210-101a08ae5547",
  "tenantID": "a2b2d6bc-afe1-4696-9c37-f97a7ac416d7"
}
[2018-08-01_10:08:58.2N] [INFO]    Evaluating the following bash variables:
adminUsername="azureuser"
appID="52e3d1d9-0f4f-47f5-b6bd-2a5457b55469"
baseUrl="https://raw.githubusercontent.com/chef-partners/chef-automate-ha/add_test_nodes_dev/"
objectId="f9842bdf-d3f1-4a31-bd24-cfc9366b35b8"
organizationName="gavinorganization"
ownerEmail="gdidrichsen@chef.io"
ownerName="gavin"
password="507ed8bf-a5b5-4c54-a210-101a08ae5547"
tenantID="a2b2d6bc-afe1-4696-9c37-f97a7ac416d7"
[
  {
    "cloudName": "AzureCloud",
    "id": "1e0b427a-d58b-494e-ae4f-ee558463ebbf",
    "isDefault": true,
    "name": "Partner Engineering",
    "state": "Enabled",
    "tenantId": "a2b2d6bc-afe1-4696-9c37-f97a7ac416d7",
    "user": {
      "name": "52e3d1d9-0f4f-47f5-b6bd-2a5457b55469",
      "type": "servicePrincipal"
    }
  }
]
[2018-08-01_10:08:59.2N] [INFO]    logged into azure
[2018-08-01_10:09:02.2N] [INFO]    deployment status for gdResourceGroupAutomate20 is Succeeded
[2018-08-01_10:09:02.2N] [INFO]    The deployment to gdResourceGroupAutomate20 succeeded
[2018-08-01_10:09:03.2N] [INFO]    raw outputs from azure deployment:[{
  "adminusername": {
    "type": "String",
    "value": "azureuser"
  },
  "chef-automate-fqdn": {
    "type": "String",
    "value": "chefautomate6h5.ukwest.cloudapp.azure.com"
  },
  "chef-automate-password": {
    "type": "String",
    "value": "The chef-automate-password is stored in the keyvault, you can retrieve it using azure CLI 2.0 [az keyvault secret show --name chefautomateuserpassword --vault-name < keyvaultname >]"
  },
  "chef-automate-url": {
    "type": "String",
    "value": "https://chefautomate6h5.ukwest.cloudapp.azure.com"
  },
  "chef-automate-username": {
    "type": "String",
    "value": "admin"
  },
  "chef-server-fqdn": {
    "type": "String",
    "value": "chefserver6h5.ukwest.cloudapp.azure.com"
  },
  "chef-server-url": {
    "type": "String",
    "value": "https://chefserver6h5.ukwest.cloudapp.azure.com"
  },
  "chef-server-webLogin-password": {
    "type": "String",
    "value": "The chef-server-weblogin-password stored in the keyvault,you can retrieve it using azure CLI 2.0 [az keyvault secret show --name chefdeliveryuserpassword --vault-name < keyvaultname >]"
  },
  "chef-server-webLogin-userName": {
    "type": "String",
    "value": "delivery"
  },
  "keyvaultName": {
    "type": "String",
    "value": "chef-key6h56z"
  }
}]
[2018-08-01_10:09:04.2N] [INFO]    writing the outputs summary to /Users/gavindidrichsen/Documents/@REFERENCE/azure/scripts/arm/chef-automate-ha/scripts/deploy/summarize_cluster/gdResourceGroupAutomate20_output.raw.json
[2018-08-01_10:09:09.2N] [INFO]    transformed outputs from azure deployment:{
  "adminusername": "azureuser",
  "chef-automate-fqdn": "chefautomate6h5.ukwest.cloudapp.azure.com",
  "chef-automate-password": "6c675e770dda2fd705f9314823cdfb9e",
  "chef-automate-url": "https://chefautomate6h5.ukwest.cloudapp.azure.com",
  "chef-automate-username": "admin",
  "chef-server-fqdn": "chefserver6h5.ukwest.cloudapp.azure.com",
  "chef-server-url": "https://chefserver6h5.ukwest.cloudapp.azure.com",
  "chef-server-webLogin-password": "507ed8bf-a5b5-4c54-a210-101a08ae5547",
  "chef-server-webLogin-userName": "delivery",
  "keyvaultName": "chef-key6h56z"
}
[2018-08-01_10:09:09.2N] [INFO]    writing the outputs summary to /Users/gavindidrichsen/Documents/@REFERENCE/azure/scripts/arm/chef-automate-ha/scripts/deploy/summarize_cluster/gdResourceGroupAutomate20_output.summary.json
[2018-08-01_10:09:12.2N] [INFO]    Exiting /Users/gavindidrichsen/Documents/@REFERENCE/azure/scripts/arm/chef-automate-ha/scripts/deploy/summarize_cluster.sh cleanly with exit code [0]
```

- Tree the output of the summarize_cluster directory.

```bash
➜  deploy git:(add_test_nodes_dev) ✗ tree summarize_cluster
summarize_cluster
├── gdResourceGroupAutomate20_delivery.pem
├── gdResourceGroupAutomate20_gavinorganization-validator.pem
├── gdResourceGroupAutomate20_output.raw.json
└── gdResourceGroupAutomate20_output.summary.json
'''
