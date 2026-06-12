locals {
  vm_datastores = {
    for k, vm in var.vms :
    k => vm.datastore != "" ? vm.datastore : var.datastore_default
  }
}
