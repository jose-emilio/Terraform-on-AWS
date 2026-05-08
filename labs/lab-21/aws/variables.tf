variable "region" {
  type        = string
  description = "Región de AWS donde se despliega la infraestructura"
  default     = "us-east-1"
}

variable "client_a_cidr" {
  type        = string
  description = "CIDR block de la VPC client-a"
  default     = "10.16.0.0/16"
}

variable "client_b_cidr" {
  type        = string
  description = "CIDR block de la VPC client-b"
  default     = "10.19.0.0/16"
}

variable "inspection_cidr" {
  type        = string
  description = "CIDR block de la VPC de inspección"
  default     = "10.17.0.0/16"
}

variable "egress_cidr" {
  type        = string
  description = "CIDR block de la VPC de salida a Internet"
  default     = "10.18.0.0/16"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado en tags y nombres de recursos"
  default     = "lab21"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"
}

variable "enable_appliance_mode" {
  type        = bool
  description = "Habilitar Appliance Mode en el attachment de la VPC de inspección (simetría de tráfico para firewalls stateful)"
  default     = true
}

variable "flow_log_retention_days" {
  type        = number
  description = "Días de retención de los VPC Flow Logs en CloudWatch"
  default     = 7
}

variable "app_account_id" {
  type        = string
  description = "ID de la cuenta de aplicación para compartir el TGW vía RAM (simulado)"
  default     = "123456789012"
}
