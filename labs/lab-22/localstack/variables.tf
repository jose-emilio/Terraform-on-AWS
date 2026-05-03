variable "region" {
  type        = string
  description = "Región declarada al provider AWS. En LocalStack es informativa (todos los servicios responden bajo el mismo endpoint local), pero se respeta para mantener paridad con la versión aws/."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado en tags y nombres de recursos"
  default     = "lab22"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"
}
