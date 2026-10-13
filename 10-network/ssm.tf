# Contrato com as camadas seguintes (ADR-0015): o 20-cluster lê estes parâmetros, não o state desta camada.
# Parâmetros nascem e morrem com a rede.

locals {
  ssm_prefix = "/guetto/network"

  contract = {
    "vpc-id"             = { type = "String", value = module.vpc.vpc_id }
    "vpc-cidr"           = { type = "String", value = module.vpc.vpc_cidr_block }
    "private-subnet-ids" = { type = "StringList", value = join(",", module.vpc.private_subnet_ids) }
    "public-subnet-ids"  = { type = "StringList", value = join(",", module.vpc.public_subnet_ids) }
  }
}

resource "aws_ssm_parameter" "contract" {
  for_each = local.contract

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Publicado pela camada 10-network (guetto-infra)."
  type        = each.value.type
  value       = each.value.value
}
