output "logs_bucket_id" {
  description = "Nombre del bucket de logs"
  value       = module.logs_bucket.bucket_id
}

output "logs_bucket_arn" {
  description = "ARN del bucket de logs"
  value       = module.logs_bucket.bucket_arn
}

output "logs_bucket_domain_name" {
  description = "Nombre de dominio del bucket de logs (formato <bucket>.s3.amazonaws.com)"
  value       = module.logs_bucket.bucket_domain_name
}

output "data_bucket_id" {
  description = "Nombre del bucket de datos"
  value       = module.data_bucket.bucket_id
}

output "data_bucket_arn" {
  description = "ARN del bucket de datos"
  value       = module.data_bucket.bucket_arn
}

output "data_bucket_domain_name" {
  description = "Nombre de dominio del bucket de datos (formato <bucket>.s3.amazonaws.com)"
  value       = module.data_bucket.bucket_domain_name
}
