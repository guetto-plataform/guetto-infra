# Budget de custo BRUTO acumulado (ADR-0011): mede o consumo dos créditos, não a fatura.
# Só notifica — não desliga nada. A proteção contra ambiente esquecido ligado é o reaper.

resource "aws_budgets_budget" "custo_bruto" {
  name         = "guetto-custo-bruto-acumulado"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"

  # CUSTOM acumula do início ao fim, sem zerar todo mês.
  # Atenção: após time_period_end a AWS apaga o budget.
  time_unit         = "CUSTOM"
  time_period_start = "${var.budget_period_start}_00:00"
  time_period_end   = "${var.budget_period_end}_00:00"

  # Sucessor recomendado de cost_types: métrica + filtro. Excluir RECORD_TYPE=Credit faz os créditos
  # não abaterem o custo; sem isso o valor ficaria ~0 até os créditos acabarem e o alerta nunca dispararia.
  metrics = ["UnblendedCost"]

  filter_expression {
    not {
      dimensions {
        key    = "RECORD_TYPE"
        values = ["Credit"]
      }
    }
  }

  dynamic "notification" {
    for_each = toset(var.budget_alert_thresholds_usd)

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "ACTUAL"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
