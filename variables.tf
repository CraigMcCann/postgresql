variable "PROXMOX_URL" {
  description = "The URL for the Proxmox environment"
  type        = string
}

variable "DEV_ROOT_PASSWORD" {
  description = "Password for the root user"
  type        = string
  default     = "" # Set via environment variable
  sensitive   = true
}

variable "PRD_ROOT_PASSWORD" {
  description = "Password for the root user"
  type        = string
  default     = "" # Set via environment variable
  sensitive   = true
}
