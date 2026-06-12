variable "datacenter" {
  description = "Nome do datacenter no vSphere"
  type        = string
}

variable "cluster" {
  description = "Nome do cluster no vSphere"
  type        = string
}

variable "template_name" {
  description = "Nome do template Linux para clonagem"
  type        = string
}

variable "datastore_default" {
  description = "Datastore padrão quando não especificado na VM"
  type        = string
}

variable "default_dns_suffix" {
  description = "Sufixo DNS padrão para VMs Linux"
  type        = string
  default     = "local"
}

variable "vms" {
  description = "Mapa de VMs Linux a serem provisionadas"
  type = map(object({
    vm_name       = string
    annotation    = optional(string, "Criado via Terraform")
    folder        = optional(string, "")
    cpus          = number
    memory_mb     = number
    datastore     = optional(string, "")
    disk_size_gb  = number
    portgroup     = string
    ip_address    = string
    netmask       = number
    gateway       = string
    dns_servers   = list(string)
    resource_pool = string

    cpu_hot_add_enabled    = optional(bool, true)
    memory_hot_add_enabled = optional(bool, true)

    extra_disks = optional(list(object({
      label            = string
      size_gb          = number
      thin_provisioned = optional(bool, true)
      unit_number      = optional(number)
    })), [])

    tags = optional(map(string), {})
  }))
}
