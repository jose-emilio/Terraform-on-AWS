variable "region" {
  type        = string
  description = "Región declarada al provider AWS. En LocalStack es informativa (todos los servicios responden bajo el mismo endpoint local), pero se respeta para mantener paridad con la versión aws/."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado en tags y nombres de recursos"
  default     = "lab24"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"

  validation {
    condition     = contains(["lab", "dev", "staging", "production"], var.environment)
    error_message = "El entorno debe ser uno de: lab, dev, staging, production."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block de la VPC (el módulo safe-network validará que sea RFC 1918)"
  default     = "10.19.0.0/16"
}

variable "bucket_name" {
  type        = string
  description = "Nombre del bucket S3 (el módulo validated-bucket validará el prefijo 'empresa-')"
}

variable "db_config" {
  type = object({
    engine                = string
    engine_version        = string
    instance_class        = string
    allocated_storage     = number
    port                  = optional(number, 3306)
    multi_az              = optional(bool, false)
    backup_retention_days = optional(number, 7)
  })

  description = "Configuración de la base de datos con campos obligatorios y opcionales."

  default = {
    engine            = "mysql"
    engine_version    = "8.0"
    instance_class    = "db.t4g.micro"
    allocated_storage = 20
  }
}

variable "db_password" {
  type        = string
  description = "Contraseña del administrador de la DB. Marcada como sensitive."
  sensitive   = true
}
