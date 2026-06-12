output "vms" {
  description = "VMs Windows provisionadas"
  value = {
    for k, vm in vsphere_virtual_machine.this :
    k => {
      name = vm.name
      ip   = vm.default_ip_address
      uuid = vm.uuid
      id   = vm.id
    }
  }
}
