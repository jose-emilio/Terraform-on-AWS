variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado como prefijo en todos los recursos"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"
}

# --- Red ---

variable "vpc_cidr" {
  type        = string
  description = "CIDR block de la VPC"
  default     = "10.20.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Zonas de disponibilidad donde desplegar. Si está vacío, se detectan automáticamente"
  default     = []
}

# --- Base de datos ---

variable "db_engine" {
  type        = string
  description = "Motor de la base de datos (mysql, postgres, mariadb)"
  default     = "mysql"

  validation {
    condition     = contains(["mysql", "postgres", "mariadb"], var.db_engine)
    error_message = "El motor debe ser uno de: mysql, postgres, mariadb."
  }
}

variable "db_engine_version" {
  type        = string
  description = "Versión del motor de la base de datos. DEBE ser <major>.<minor> (ej: '8.0', '15.4'), NO incluir patch ('8.0.35' falla porque se usa para construir el `family` del parameter group de RDS, que solo acepta major.minor)."
  default     = "8.0"

  validation {
    # Solo aceptamos formato <major>.<minor> con dígitos a ambos lados.
    # Esto evita que alguien pase "8.0.35" o "8" y rompa la construccion
    # del family ("mysql8.0.35" o "mysql8" no son values validos en RDS).
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.db_engine_version))
    error_message = "db_engine_version debe tener formato <major>.<minor> (ejemplos válidos: '8.0', '15.4', '13.10'). Sin patch version."
  }
}

variable "db_instance_class" {
  type        = string
  description = "Clase de instancia RDS"
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "Almacenamiento asignado en GB"
  default     = 20
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos inicial"
  default     = "appdb"
}

variable "db_username" {
  type        = string
  description = "Nombre del usuario administrador"
  default     = "admin"
}

variable "db_port" {
  type        = number
  description = "Puerto de la base de datos"
  default     = 3306
}

variable "multi_az" {
  type        = bool
  description = "Habilitar Multi-AZ para alta disponibilidad"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Etiquetas adicionales para todos los recursos"
  default     = {}
}
