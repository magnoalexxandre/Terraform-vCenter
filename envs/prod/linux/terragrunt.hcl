include "root" {
  path = find_in_parent_folders()
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  vm_files = fileset("${get_terragrunt_dir()}/vms", "*.yaml")
  vms = {
    for f in local.vm_files :
    trimsuffix(f, ".yaml") => yamldecode(file("${get_terragrunt_dir()}/vms/${f}"))
  }
}

terraform {
  source = "${get_terragrunt_dir()}/../../../modules/vm-linux"
}

inputs = {
  datacenter         = local.env_vars.locals.datacenter
  cluster            = local.env_vars.locals.cluster
  datastore_default  = local.env_vars.locals.datastore_default
  template_name      = "TEMPLATE-LINUX-PROD"
  default_dns_suffix = "prod.meudominio.com"

  vms = local.vms
}
