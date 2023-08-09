import json
import subprocess

def lambda_handler(event, _):
    # Parse the input event JSON
  try:
    input_data = json.loads(event['body'])


    print(subprocess.check_output('sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    print(subprocess.check_output('sudo chmod +x kubectl"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    print(subprocess.check_output('sudo mv kubectl /usr/local/bin"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    
    print(subprocess.check_output('wget https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_linux_amd64.zip"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    print(subprocess.check_output('unzip terraform_1.4.6_linux_amd64.zip"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    print(subprocess.check_output('sudo mv terraform /usr/local/bin"', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    
    branch = input_data['GitBranch']

    print(subprocess.check_output(f"git clone -b {branch} https://github.com/Discngine/quickstart-discngine-3decision.git", shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    
    region = input_data['Region']
    bucket = input_data['Bucket']

    with open("backend.conf", "w") as config_file:
      config_file.write(f'region = "{region}"\nbucket = "{bucket}"')
    
    with open("vars.tfvars", "w") as var_file:
      var_file.write(f'''
                    region = "{region}"
                    keypair_name = {input_data["ForceDestroy"]}
                    public_final_snapshot = {input_data["CreateFinalSnapshot"]}
                    private_final_snapshot = {input_data["CreateFinalSnapshot"]}
                    skip_db_final_snapshot = {input_data["SkipFinalSnapshot"]}
                    create_network = false
                    vpc_id = "{input_data["VPCID"]}"
                    private_subnet_ids = ["{input_data["PrivateSubnet1ID"]}", "{input_data["PrivateSubnet2ID"]}", "{input_data["PrivateSubnet3ID"]}"]
                    custom_ami = "{input_data["CustomAmiId"]}"
                    db_snapshot_identifier = "{input_data["DBSnapshotIdentifier"]}"
                    db_high_availability = {input_data["DBMultiZone"]}
                    db_backup_retention_period = {input_data["DBBackupRetentionPeriod"]}
                    db_delete_automated_backups = {input_data["DBDeleteAutoBackups"]}
                    load_balancer_type = "{input_data["LoadBalancerType"]}"
                    certificate_arn = "{input_data["CertificateArn"]}"
                    domain = "{input_data["DomainName"]}"
                    main_subdomain = "{input_data["MainSubdomain"]}"
                    additional_main_subdomains = [{input_data["AdditionalMainSubdomains"]}]
                    api_subdomain = "{input_data["ApiSubdomain"]}"
                    hosted_zone_id = "{input_data["HostedZoneId"]}"
                    azure_oidc = {{
                      client_id = "{input_data["AzureClient"]}"
                      tenant    = "{input_data["AzureTenant"]}"
                      secret    = "{input_data["AzureSecret"]}"
                    }}
                    okta_oidc = {{
                      client_id = "{input_data["OktaClient"]}"
                      domain    = "{input_data["OktaDomain"]}"
                      server_id = "{input_data["OktaServerId"]}"
                      secret    = "{input_data["OktaSecret"]}"
                    }}
                    google_oidc = {{
                      client_id = "{input_data["GoogleClient"]}"
                      secret    = "{input_data["GoogleSecret"]}"
                    }}
                    public_volume_snapshot = "{input_data["PublicVolumeSnapshotId"]}"
                    private_volume_snapshot = "{input_data["PrivateVolumeSnapshotId"]}"

                    kubernetes_version = "{input_data["KubernetesVersion"]}"
                    db_instance_type = "{input_data["DBInstanceClass"]}"
                    license_type = "license-included"
                    eks_instance_type = "{input_data["NodeInstanceType"]}"
                    boot_volume_size = "{input_data["NodeVolumeSize"]}"

                    additional_eks_users_arn = [{input_data["AdditionalEKSAdminUserArn"]}]
                    additional_eks_roles_arn = [{input_data["AdditionalEKSAdminRoleArn"]}]

                    tdecision_chart = {{
                      version = {input_data["TdecisionVersion"]}
                      namespace = "{input_data["TdecisionNamespace"]}"
                    }}
                     ''')
    print(subprocess.check_output("terraform init -backend-config=backend.conf -reconfigure -upgrade", shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
    print(subprocess.check_output(f'terraform {input_data["StackOperation"]} -var-file=vars.tfvars -auto-approve', shell=True, stderr=subprocess.STDOUT, universal_newlines=True))
  except subprocess.CalledProcessError as error:
    print("Command failed with error:")
    print(error.output)

    # Create a response
    response = {
        "statusCode": 200,
#        "body": json.dumps({"result": result})
    }
    
    return response