locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment

  minio_endpoint = get_env("MINIO_ENDPOINT", "https://minio-des.meudominio.com")
  minio_bucket   = "terraform-vcenter-state"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "vsphere" {
      vsphere_server       = var.vsphere_server
      user                 = var.vsphere_user
      password             = var.vsphere_password
      allow_unverified_ssl = true
    }
  EOF
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = local.minio_bucket
    key    = "${path_relative_to_include()}/terraform.tfstate"

    endpoints = {
      s3 = local.minio_endpoint
    }

    region                      = "us-east-1"
    access_key                  = get_env("MINIO_ACCESS_KEY", "")
    secret_key                  = get_env("MINIO_SECRET_KEY", "")
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}

inputs = {
  vsphere_server   = get_env("VSPHERE_SERVER", "")
  vsphere_user     = get_env("VSPHERE_USER", "")
  vsphere_password = get_env("VSPHERE_PASSWORD", "")
}
