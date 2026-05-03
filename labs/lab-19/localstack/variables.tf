variable "region" {
  type        = string
  description = "Región declarada al provider AWS. En LocalStack es informativa (todos los servicios responden bajo el mismo endpoint local), pero se respeta para mantener paridad con la versión aws/."
  default     = "us-east-1"
}

variable "app_cidr" {
  type        = string
  description = "CIDR block de la VPC app"
  default     = "10.15.0.0/16"
}

variable "db_cidr" {
  type        = string
  description = "CIDR block de la VPC db"
  default     = "10.16.0.0/16"
}

variable "c_cidr" {
  type        = string
  description = "CIDR block de la VPC C"
  default     = "10.17.0.0/16"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado en tags y nombres de recursos"
  default     = "lab19"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"
}
