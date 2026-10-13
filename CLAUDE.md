# guetto-infra

Terraform da Guetto Platform: bootstrap da conta, rede, EKS, IAM e instalação inicial do Argo CD.
Tudo o que roda dentro do cluster depois do Argo CD pertence ao `guetto-gitops`, não a este repo.
Decisões em `guetto-plataform/.github` → `docs/adr/` (principalmente ADR-0002, 0003, 0010).

## Camadas (um state por camada)

| Pasta | Ciclo de vida | Quem aplica |
|---|---|---|
| `00-bootstrap` | Persistente, uma vez por conta | **Somente humano**, local (ADR-0011). State migrado para `00-bootstrap/` no bucket da própria conta |
| `10-network` | Efêmera (`make up` / `make down`) | Humano ou CI |
| `20-cluster` | Efêmera | Humano ou CI |

## Regras

- **Nunca commitar:** `*.tfstate`, planos (`*.tfplan`), `.terraform/`, nem nada em `accounts/<conta>/`
  além de `accounts/example/`. O repo é público.
- **Nunca fixar no código:** account ID, ARN, nome de bucket ou nome de profile. Usar
  `data.aws_caller_identity`, variáveis e `accounts/<conta>/`.
- `.terraform.lock.hcl` **é** versionado; versões de Terraform e providers são fixadas.
- Módulos da biblioteca `vitorfprado/terraform-aws-modules` são consumidos por tag (`?ref=vX.Y.Z`);
  ajuste em módulo = PR + release na biblioteca, nunca cópia local.
- Todo recurso recebe as tags padrão via `default_tags` do provider (`project=guetto`, `layer=<camada>`).

## Comandos

Interface de operação: **scripts bash em `scripts/`** (sem Makefile — ADR-0011). Seleção de conta via
`accounts/<conta>/` (`account.env` com `AWS_PROFILE`, `account.tfvars`, `backend.hcl`).

| Comando | O que faz |
|---|---|
| `scripts/bootstrap.sh <conta> [--plan]` | Aplica `00-bootstrap` (primeira execução: backend local + migração para o S3) |

- No Windows, rodar os scripts **no Git Bash**. O `bash` do PATH do Windows é o do WSL (outro ambiente, outras credenciais).
- Scripts: `#!/usr/bin/env bash` + `set -euo pipefail`, finais de linha LF (`.gitattributes`), sem avisos do `shellcheck`.
- Arquivos de `accounts/` são **lidos com `sed`**, nunca com `source` (não executar config; tolerar CRLF).
