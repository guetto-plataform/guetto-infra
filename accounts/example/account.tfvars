# Copie esta pasta para accounts/<conta>/ (não versionada) e preencha com os dados reais.
account_name = "example" # = nome desta pasta; vira o GitHub Environment aws-<account_name> (público)
account_id   = "123456789012"
region       = "us-east-1"

# Budget (ADR-0011). Fim do período = expiração dos créditos (console: Billing > Credits).
budget_email        = "voce@example.com"
budget_period_start = "2026-01-01"
budget_period_end   = "2027-01-01"
