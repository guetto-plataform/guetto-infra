variable "account_id" {
  description = "ID da conta AWS alvo (trava allowed_account_ids)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id deve ter exatamente 12 dígitos."
  }
}

variable "region" {
  description = "Região AWS da plataforma."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Nome base dos recursos de rede."
  type        = string
  default     = "guetto"
}

# Plano de endereçamento do ADR-0013. A quantidade de AZs é dada pelo tamanho das listas.
variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Subnets privadas (nós e pods), uma por AZ."
  type        = list(string)
  default     = ["10.20.0.0/19", "10.20.32.0/19", "10.20.64.0/19"]
}

variable "public_subnet_cidrs" {
  description = "Subnets públicas (load balancers e NAT), uma por AZ."
  type        = list(string)
  default     = ["10.20.96.0/24", "10.20.97.0/24", "10.20.98.0/24"]
}

variable "eks_unsupported_zone_ids" {
  description = "IDs de AZ onde o EKS não aceita subnets (doc EKS — requisitos de rede). IDs são únicos por região."
  type        = list(string)
  default     = ["use1-az3", "usw1-az2", "cac1-az3"]
}
