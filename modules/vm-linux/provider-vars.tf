variable "vsphere_server" {
  description = "Endereço do vCenter Server"
  type        = string
}

variable "vsphere_user" {
  description = "Usuário do vCenter"
  type        = string
}

variable "vsphere_password" {
  description = "Senha do vCenter"
  type        = string
  sensitive   = true
}
