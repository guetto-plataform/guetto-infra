# Rede da plataforma (ADR-0013): 3 AZs, subnets privadas para nós/pods, públicas só para LB e NAT.

# AZs escolhidas por ID, não por nome: o mapeamento nome -> ID muda por conta, e o EKS rejeita algumas AZs.
data "aws_availability_zones" "eks" {
  state            = "available"
  exclude_zone_ids = var.eks_unsupported_zone_ids

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"] # exclui Local Zones e Wavelength
  }
}

locals {
  azs = slice(data.aws_availability_zones.eks.names, 0, length(var.private_subnet_cidrs))
}

module "vpc" {
  source = "git::https://github.com/vitorfprado/terraform-aws-modules.git//vpc?ref=v1.1.0"

  name       = var.name
  cidr_block = var.vpc_cidr
  azs        = local.azs

  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  # NAT gerenciado único (ADR-0003); nada recebe IP público automático.
  enable_nat_gateway      = true
  single_nat_gateway      = true
  map_public_ip_on_launch = false

  enable_s3_gateway_endpoint = true

  # Descoberta de subnets pelo AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
