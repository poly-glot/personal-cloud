# personal-cloud
The cloud setup relies on a Kubernetes cluster hosted on Oracle Cloud and facilitates the synchronization of crucial
secrets across my various personal projects.

## System requirements
You’ll want to ensure you have the following already installed on your local machine before getting started:
* [Docker](https://docs.docker.com/get-docker/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Setup Instructions
1. Clone/Fork this repository
2. Setup following secrets by visiting Setting -> Secrets and variables -> Actions
```
PERSONAL_GITHUB_TOKEN_CLASSIC
OCI_CLI_USER
OCI_CLI_TENANCY
OCI_CLI_FINGERPRINT
OCI_CLI_KEY_CONTENT
OCI_CLI_REGION
OCI_COMPARTMENT_OCID
OCI_AUTH_TOKEN
```

**Note:** 
- [Click here](https://github.com/settings/tokens) to create Github classic tokens (PERSONAL_GITHUB_TOKEN_CLASSIC).
- [Click here](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/terraformproviderconfiguration.htm#ariaid-title3) to follow OCI API Key Authentication ((Useful Information)[https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#Required_Keys_and_OCIDs])
- [Finding the OCID of a Compartment](https://docs.oracle.com/en-us/iaas/Content/GSG/Tasks/contactingsupport_topic-Finding_the_OCID_of_a_Compartment.htm) - ((Direct Link)[https://cloud.oracle.com/identity/compartments?region=uk-london-1])

## Access Oracle Docker Registry Locally
- Find Region ID from [Availability Zones](https://docs.oracle.com/en-us/iaas/Content/Registry/Concepts/registryprerequisites.htm#regional-availability). For example UK South London id is "lhr"
- Find Tenancy Namespace Id (or aka Object storage namespace) - https://cloud.oracle.com/identity/compartments?region=uk-london-1
- Generate Auth token - https://cloud.oracle.com/identity/compartments?region=uk-london-1
```shell
docker login {region-id}.ocir.io --username={tenancy-namespace}/oracleidentitycloudservice/{email}
```
- Provide Auth token when prompted for password.
