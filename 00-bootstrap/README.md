# 00-bootstrap

Camada **persistente**, aplicada **uma vez por conta**, **somente por humano** (ADR-0011).
Cria a base que as outras camadas pressupõem: bucket do state, budget e (em breve) acesso OIDC da CI.

## O que esta camada cria

| Parte | Conteúdo | Status |
|---|---|---|
| Bucket do state | 1 bucket S3 + 6 configurações ([state.tf](state.tf)) | Implementado |
| Budget | 1 AWS Budget de custo bruto acumulado, avisos em US$ 75 e US$ 150 ([budget.tf](budget.tf)) | Implementado |
| Acesso da CI | OIDC provider do GitHub + role IAM + GitHub Environment `aws-<conta>` ([ci-oidc.tf](ci-oidc.tf), [github.tf](github.tf)) | Implementado |

Nada aqui cobra por hora; o custo do bucket é de centavos por ano.

### Bucket do state

Na AWS existe **um** bucket. Os outros recursos são configurações dele: desde a v4 do provider, cada
configuração (uma chamada de API distinta) é um recurso Terraform separado.

```
s3://guetto-tfstate-<account-id>-<região>-an
 ├── 00-bootstrap/terraform.tfstate   (state desta camada, após a migração)
 ├── 10-network/terraform.tfstate
 └── 20-cluster/terraform.tfstate
```

| Recurso | O que faz | Sem ele… | Doc oficial |
|---|---|---|---|
| `aws_s3_bucket` | Bucket no **namespace regional da conta** (sufixo `-an`): nenhuma outra conta pode criar o nome, nem após exclusão. `prevent_destroy` faz o Terraform recusar planos que o apaguem | Nome previsível poderia ser registrado por terceiros; um `destroy` acidental levaria o histórico de todas as camadas | [Namespaces](https://docs.aws.amazon.com/AmazonS3/latest/userguide/gpbucketnamespaces.html) · [`prevent_destroy`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) |
| `aws_s3_bucket_versioning` | Cada escrita do state vira uma versão; as anteriores ficam recuperáveis | State corrompido ou sobrescrito sem volta | [Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html) |
| `aws_s3_bucket_server_side_encryption_configuration` | Criptografia em repouso SSE-S3 (gratuita). Já é o padrão da AWS; declarada para o requisito ficar explícito | Nada muda hoje — é documentação executável | [Default encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html) |
| `aws_s3_bucket_public_access_block` | Proíbe acesso público, mesmo diante de política ou ACL mal configurada | O state (que pode conter segredos) ficaria a um erro de configuração de ser exposto | [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html) |
| `aws_s3_bucket_ownership_controls` | `BucketOwnerEnforced`: desliga ACLs; acesso só por políticas IAM | Dois sistemas de permissão para auditar | [Object Ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) |
| `aws_s3_bucket_policy` | Nega qualquer requisição sem TLS (`aws:SecureTransport = false`) | State poderia trafegar sem criptografia | [Security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html) |
| `aws_s3_bucket_lifecycle_configuration` | Mantém as 10 versões antigas mais recentes (demais expiram em 90 dias); limpa uploads incompletos e delete markers | Cada lock cria e apaga um `.tflock`; com versionamento, o lixo acumularia para sempre | [Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) |

O `data "aws_iam_policy_document"` no plan não cria nada: só gera o JSON da bucket policy a partir de HCL.

### Budget

| Configuração | Valor | Por quê |
|---|---|---|
| `metrics = ["UnblendedCost"]` + `filter_expression` excluindo `RECORD_TYPE = Credit` | Custo **bruto** | Com créditos abatendo, o custo fica ~0 e o alerta nunca dispara. Substitui o `cost_types.include_credit`, deprecated na API ([Budget API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_budgets_Budget.html), [dimensões](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_budgets_ExpressionDimensionValues.html)) |
| `time_unit = "CUSTOM"` | Acumulado de `budget_period_start` até `budget_period_end` | Não zera todo mês. **Após a data final a AWS apaga o budget** ([custom periods](https://aws.amazon.com/about-aws/whats-new/2025/09/aws-budgets-custom-time-periods)) |
| 2 notificações `ACTUAL` | US$ 75 e US$ 150 | Valor absoluto, por e-mail |

Só notifica; não desliga recursos. O e-mail **precisa ser verificado**: a AWS envia um link (de `@aws.com`, expira em
12h) que exige login na conta; sem isso nenhum alerta é entregue
([verificação](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-email-recipients.html)).

### Acesso da CI (OIDC)

```
job com environment: aws-<conta> ──JWT──▶ STS ──▶ role guetto-github-actions (credenciais de até 2h)
  (só o main pode usar o environment)         confere aud + sub na trust policy
```

| Recurso | O que faz | Doc oficial |
|---|---|---|
| `aws_iam_openid_connect_provider` | Registra `token.actions.githubusercontent.com` como emissor confiável nesta conta | [IAM OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) |
| `aws_iam_role` + trust policy | Só aceita `aud = sts.amazonaws.com` e o `sub` exato do environment (output `github_oidc_subject`) | [GitHub OIDC na AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) |
| `aws_iam_role_policy_attachment` | `AdministratorAccess` — risco aceito no ADR-0012 | — |
| `aws_iam_role_policy` (guardrails) | Deny: a role não altera a si mesma, o OIDC provider, o budget, o state `00-bootstrap/` nem a config do bucket | [Lógica de avaliação](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) |
| `github_repository_environment` + deployment policy | Environment `aws-<conta>` que só o branch `main` pode usar | [Environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) |
| `github_actions_environment_secret` / `_variable` | Secrets `AWS_ROLE_ARN`, `TF_STATE_BUCKET` (contêm o account ID; mascarados nos logs) e variável `AWS_REGION` | — |

O provider do GitHub lê o token de `GITHUB_TOKEN`: `export GITHUB_TOKEN=$(gh auth token)` antes do plan/apply.
Validação: workflow [aws-oidc-smoke-test](../.github/workflows/aws-oidc-smoke-test.yml).

### Por que o primeiro apply usa backend local

O backend é lido no `terraform init`, antes de qualquer recurso existir — e o bucket que vai guardar o state é
criado por esta própria camada. Por isso: apply com backend local (`backend_override.tf`, um
[override file](https://developer.hashicorp.com/terraform/language/files/override)) e, com o bucket criado,
[`terraform init -migrate-state`](https://developer.hashicorp.com/terraform/cli/commands/init) copia o state para
dentro dele. Lock: arquivo `.tflock` ao lado do state (`use_lockfile`) —
[backend S3](https://developer.hashicorp.com/terraform/language/backend/s3). Decisão em ADR-0011.

## Primeira execução numa conta

Procedimento manual. Será automatizado em `scripts/bootstrap.sh` quando a camada estiver completa.
Rodar no **Git Bash**, a partir da raiz do `guetto-infra`.

```bash
# 0. Config da conta (pasta não versionada). <conta> é um apelido local, ex.: lab.
cp -r accounts/example accounts/<conta>
aws sts get-caller-identity --query Account --output text --profile <profile>   # -> account_id
#    Preencha account_id em account.tfvars e o nome do bucket em backend.hcl.
export AWS_PROFILE=<profile>
cd 00-bootstrap

# 1. Primeiro apply com backend LOCAL: o bucket do backend S3 ainda não existe.
#    *_override.tf é ignorado pelo Git e substitui o bloco backend de versions.tf.
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {}
}
EOF
terraform init -reconfigure
terraform plan -var-file=../accounts/<conta>/account.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan

# 2. Migrar o state para dentro do bucket recém-criado.
rm backend_override.tf
terraform init -migrate-state -backend-config=../accounts/<conta>/backend.hcl
terraform state list          # deve listar os recursos, agora lidos do S3
rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
```

## Execuções seguintes (conta já inicializada)

```bash
export AWS_PROFILE=<profile>
export GITHUB_TOKEN=$(gh auth token)
terraform init -reconfigure -backend-config=../accounts/<conta>/backend.hcl
terraform plan -var-file=../accounts/<conta>/account.tfvars
```

## Destruir (raro)

Exige remover `prevent_destroy` do bucket, migrar o state de volta para local (passo 1 ao contrário) e esvaziar
todas as versões do bucket. Não automatizado de propósito.
