terraform {
  backend "s3" {
    bucket                      = "terraform-backend"
    key                         = "junaidcloud/terraform.tfstate"
    region                      = "uk-london-1"
    endpoint                    = "https://lrhvckxzwf3l.compat.objectstorage.uk-london-1.oraclecloud.com"
    shared_credentials_file     = "../terraform-states_bucket_credentials"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=5.8.0"
    }
  }
}
