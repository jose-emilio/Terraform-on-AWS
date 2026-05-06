variable "region" {
  type        = string
  description = "Región usada en el service_name del VPC Endpoint (en LocalStack los endpoints son emulados, pero el ARN se respeta)"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block de la VPC"
  default     = "10.13.0.0/16"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto, usado en tags y nombres de recursos"
  default     = "lab17"
}

variable "environment" {
  type        = string
  description = "Entorno de despliegue (lab, dev, staging, production)"
  default     = "lab"
}

# Nota: en la versión aws/ existe `use_nat_instance` para alternar entre NAT
# Gateway y NAT Instance. En LocalStack siempre se despliega NAT Gateway
# (la NAT Instance requiere AMI real de EC2), por lo que esa variable se omite.
