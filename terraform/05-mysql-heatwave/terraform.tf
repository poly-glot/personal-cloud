terraform {
  backend "s3" {
    bucket                      = "terraform-backend"
    key                         = "junaidcloud/mysql-heatwave.tfstate"
    region                      = "uk-london-1"
    endpoint                    = "https://lrhvckxzwf3l.compat.objectstorage.uk-london-1.oraclecloud.com"
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
