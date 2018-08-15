# See https://docs.getchef.com/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "{{cookiecutter.chefserver_username}}"
validation_client_name   "{{cookiecutter.chefserver_organization}}-validator"
validation_key           "/etc/chef/{{cookiecutter.chefserver_organization}}-validator.pem"
client_key               "#{current_dir}/{{cookiecutter.chefserver_username}}.pem"
chef_server_url          "https://{{cookiecutter.chefserver_public_dns}}/organizations/{{cookiecutter.chefserver_organization}}"
cookbook_path            ["#{current_dir}/../cookbooks"]
identity_file            "{{cookiecutter.ssh_identity_file}}"
