# personal-cloud

This project create a Kubernetes cluster using terraform on Oracle Cloud, also enable the seamless synchronization of secrets among
interconnected projects. This synchronization allows these projects to deploy their applications on the cluster effectively.

## System requirements
You’ll want to ensure you have the following already installed on your local machine before getting started:
* [Docker](https://docs.docker.com/get-docker/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [oci-cli](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)

## Setup Instructions
1. Clone/Fork this repository
2. [Click here](https://github.com/settings/tokens) to create Github classic tokens and store them as `PERSONAL_GITHUB_TOKEN_CLASSIC` in repository secret under Setting -> Secrets and variables -> Actions 
3. Login to [Oracle Cloud](https://console.uk-london-1.oraclecloud.com/), Click on Profile Icon and your username e.g. "oracleidentitycloudservice/{{email}}"
4. Click on API Keys under "Resources" section
5. Click "Add Key" and supply an API Key (You can use Generate API Key Pair option if you do not have a key)
6. Click on "three dots" and view Configuration file
7. Paste the content of the file with correct key_file location (keys generated in step 5) in "~/.oci/config" as instructed
```shell
# To verify oci authentication
oci iam compartment list --compartment-id-in-subtree=true
```
8. Setup following secrets in your repository by visiting Setting -> Secrets and variables -> Actions
9. Add following secrets in the repository based on configuration file under Setting -> Secrets and variables -> Actions
```
OCI_CLI_USER
OCI_CLI_TENANCY
OCI_CLI_FINGERPRINT
OCI_CLI_KEY_CONTENT
OCI_CLI_REGION
```
10. Click on "Auth Tokens" in the left hand side under "Resources" tab
11. Generate token and store as `OCI_AUTH_TOKEN` in Repository secrets
12. [Click here](https://docs.oracle.com/en-us/iaas/Content/GSG/Tasks/contactingsupport_topic-Finding_the_OCID_of_a_Compartment.htm) to find the OCID of a Compartment - ((Direct Link)[https://cloud.oracle.com/identity/compartments?region=uk-london-1])
13. Store `OCI_COMPARTMENT_OCID` in Repository secrets
14. Click on Profile icon in Oracle Cloud and visit "Tenancy: {{yourid}}" link
15. Copy "Object storage namespace" and store as `OCI_TENANCY_NAMESPACE` in Repository secrets
16. Find Region ID from [Availability Zones](https://docs.oracle.com/en-us/iaas/Content/Registry/Concepts/registryprerequisites.htm#regional-availability). For example UK South London id is "lhr" and store the following host as `DOCKER_HOST` in secrets
```shell
{region-id}.ocir.io
```
17. Store `DOCKER_USERNAME` as following, where `OCI_USERNME` is same as appeared in Oracle Cloud under Profile icon "oracleidentitycloudservice/{{email}}"
```shell
$OCI_TENANCY_NAMESPACE/$OCI_USERNME

# To test docker credentials locally
echo $OCI_AUTH_TOKEN | docker login $DOCKER_HOST --username=$DOCKER_USERNAME --password-stdin
```
18. Visit Oracle Cloud and search "Buckets" OR Click Burger Menu -> Storage -> Object Storage & Archive Storage -> Buckets
19. Click "Create Bucket" and name it appropriately because it will save terraform states. I usually call them "terraform-backend"
20. Update following files
- Replace bucket name
- Replace endpoint, it is usually "https://$OCI_TENANCY_NAMESPACE.compat.objectstorage.$OCI_REGION.oraclecloud.com"
- Name key appropriately or leave it as it is.
```shell
terraform/01-infrastructure/terraform.tf
terraform/03-network-loadbalancer/terraform.tf
```
21. Push all changes, Visit Actions tab in your repository and manually run " 01 - Deploy Core Infrastructure Changes"

### Name nodes in the cluster
1. Create kubeconfig file locally
```shell
oci ce cluster create-kubeconfig --cluster-id $OCI_COMPARTMENT_OCID --file ~/.kube/oci --region $OCI_CLI_REGION --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT  --overwrite
export KUBECONFIG=~/.kube/oci
```

2. Run the following command to see the nodes and their labels. It will display NodeId - Label - Display Name OCID
```shell
kubectl get nodes --output=jsonpath='{range .items[*]}{@.metadata.name}{"\t"}{@.metadata.labels.kubernetes\.io/hostname}{"\t"}{@.metadata.labels.displayName}{"\t"}{@.spec.providerID}{"\n"}{end}'

# In case you want to see node pool id
kubectl get nodes --output=jsonpath='{range .items[*]}{@.metadata.name}{"\t"}{@.metadata.labels.kubernetes\.io/hostname}{"\t"}{@.metadata.labels.displayName}{"\t"}{@.spec.providerID}{"\t"}{@.metadata.annotations.oci\.oraclecloud\.com/node-pool-id}{"\n"}{end}'
```

3. Label each node so that we can target them for pod placement later on 
```shell
kubectl label node NODE_ID_1 "kubernetes.io/hostname"="main" --overwrite
kubectl label node NODE_ID_2 "kubernetes.io/hostname"="node1" --overwrite
...
kubectl label node NODE_ID_4 "kubernetes.io/hostname"="node4" --overwrite
```

4. Copy the OCID of main node and store it as Repository Secret `OCI_MAIN_INSTANCE_OCID` in Github.

### Setup Network Load Balancer
1. Goto Repository -> Actions -> 03 - Deploy OCI Network Loadbalancer
2. Run the action manually
3. You can use public ip address in DNS setup
