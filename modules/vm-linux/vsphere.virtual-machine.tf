resource "vsphere_virtual_machine" "this" {
  for_each = var.vms

  name             = upper(each.value.vm_name)
  resource_pool_id = data.vsphere_resource_pool.this[each.key].id
  datastore_id     = data.vsphere_datastore.this[each.key].id
  folder           = each.value.folder
  annotation       = "${each.value.annotation} | IP: ${each.value.ip_address}"

  num_cpus = each.value.cpus
  memory   = each.value.memory_mb

  cpu_hot_add_enabled    = each.value.cpu_hot_add_enabled
  memory_hot_add_enabled = each.value.memory_hot_add_enabled

  guest_id  = data.vsphere_virtual_machine.this.guest_id
  firmware  = data.vsphere_virtual_machine.this.firmware
  scsi_type = data.vsphere_virtual_machine.this.scsi_type

  network_interface {
    network_id   = data.vsphere_network.this[each.key].id
    adapter_type = data.vsphere_virtual_machine.this.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size_gb
    thin_provisioned = data.vsphere_virtual_machine.this.disks[0].thin_provisioned
  }

  dynamic "disk" {
    for_each = each.value.extra_disks
    content {
      label            = disk.value.label
      size             = disk.value.size_gb
      thin_provisioned = disk.value.thin_provisioned
      unit_number      = disk.value.unit_number
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.this.id

    customize {
      linux_options {
        host_name = lower(each.value.vm_name)
        domain    = var.default_dns_suffix
      }

      network_interface {
        ipv4_address = each.value.ip_address
        ipv4_netmask = each.value.netmask
      }

      ipv4_gateway    = each.value.gateway
      dns_server_list = each.value.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [
      clone,
      guest_id,
      scsi_type,
      firmware,
    ]
  }
}
