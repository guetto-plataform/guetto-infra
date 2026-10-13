output "vpc_id" {
  description = "ID da VPC."
  value       = module.vpc.vpc_id
}

output "azs" {
  description = "AZs usadas (nomes desta conta)."
  value       = local.azs
}

output "private_subnet_ids" {
  description = "Subnets privadas (nós e pods)."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Subnets públicas (load balancers e NAT)."
  value       = module.vpc.public_subnet_ids
}

output "ssm_parameters" {
  description = "Parâmetros SSM publicados como contrato para as próximas camadas."
  value       = [for p in aws_ssm_parameter.contract : p.name]
}
