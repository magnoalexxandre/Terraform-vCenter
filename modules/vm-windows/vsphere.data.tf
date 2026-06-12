data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_virtual_machine" "this" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_datastore" "this" {
  for_each      = local.vm_datastores
  name          = each.value
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  for_each      = var.vms
  name          = each.value.portgroup
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_resource_pool" "this" {
  for_each      = var.vms
  name          = each.value.resource_pool
  datacenter_id = data.vsphere_datacenter.this.id
}
