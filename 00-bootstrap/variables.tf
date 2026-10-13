variable "account_id" {
  description = "ID da conta AWS alvo. Usado na trava allowed_account_ids e no nome do bucket."
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

variable "account_name" {
  description = "Apelido da conta (nome da pasta em accounts/). Vira o GitHub Environment aws-<account_name>; é público."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.account_name))
    error_message = "Use apenas letras minúsculas, números e hífen."
  }
}

variable "github_owner" {
  description = "Organização do GitHub dona do repositório."
  type        = string
  default     = "guetto-plataform"
}

# Lido por variável e não pelo data source github_organization, que exige escopo read:user no token.
# O ID é imutável por definição (é o que protege o sub contra reciclagem de nome).
variable "github_owner_id" {
  description = "ID numérico da organização (gh api orgs/<org> --jq .id)."
  type        = number
  default     = 341944408
}

variable "github_repository" {
  description = "Repositório cujos workflows podem assumir a role da CI."
  type        = string
  default     = "guetto-infra"
}

variable "budget_email" {
  description = "E-mail que recebe os alertas do budget. Precisa ser verificado (link expira em 12h)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email deve ser um endereço de e-mail válido."
  }
}

variable "budget_limit_usd" {
  description = "Limite do budget de custo bruto acumulado, em USD."
  type        = string
  default     = "150"
}

variable "budget_alert_thresholds_usd" {
  description = "Valores (USD, custo bruto acumulado) que disparam alerta por e-mail."
  type        = list(number)
  default     = [75, 150]
}

variable "budget_period_start" {
  description = "Início do período acumulado (AAAA-MM-DD). Data fixa: timestamp() geraria diff a cada plan."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_period_start))
    error_message = "Use o formato AAAA-MM-DD."
  }
}

variable "budget_period_end" {
  description = "Fim do período (AAAA-MM-DD) = expiração dos créditos (console: Billing > Credits)."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_period_end))
    error_message = "Use o formato AAAA-MM-DD."
  }
}
