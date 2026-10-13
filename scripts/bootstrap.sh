#!/usr/bin/env bash
# Aplica a camada 00-bootstrap numa conta AWS (ADR-0011). Somente humano, local, no Git Bash.
#
# Uso: scripts/bootstrap.sh <conta> [--plan]
#   <conta>   pasta accounts/<conta>/ com account.env, account.tfvars e backend.hcl
#   --plan    só mostra o plano; não aplica nada
#
# Primeira execução numa conta (bucket do state ainda não existe):
#   apply com backend local temporário -> migra o state para o bucket recém-criado.
# Execuções seguintes: init no backend S3 -> plan -> confirmação -> apply.
set -euo pipefail

readonly EXAMPLE_ACCOUNT_ID="123456789012"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly layer_dir="$repo_root/00-bootstrap"
readonly override_file="$layer_dir/backend_override.tf"
readonly plan_file="bootstrap.tfplan" # relativo a layer_dir (terraform -chdir)

conta=""
plan_only=false

log() { printf '\n==> %s\n' "$*"; }
die() {
  printf '\nERRO: %s\n' "$*" >&2
  exit 1
}
usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'; }

# Terraform sempre roda dentro da camada; caminhos de arquivo são relativos a ela.
tf() { terraform -chdir="$layer_dir" "$@"; }

# Lê `chave = "valor"` (tfvars/hcl) ou `CHAVE=valor` (env) sem executar o arquivo; tolera CRLF.
read_hcl() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$2" | tr -d '\r' | head -n1; }
read_env() { sed -nE "s/^[[:space:]]*$1=\"?([^\"[:space:]]*)\"?.*/\1/p" "$2" | tr -d '\r' | head -n1; }

cleanup() {
  # O override só pode existir durante a primeira execução; nunca deve sobrar no disco.
  rm -f "$override_file" "$layer_dir/$plan_file"
}
trap cleanup EXIT

parse_args() {
  while (($#)); do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --plan) plan_only=true ;;
      -*) die "opção desconhecida: $1" ;;
      *)
        [[ -z "$conta" ]] || die "informe apenas uma conta"
        conta="$1"
        ;;
    esac
    shift
  done
  [[ -n "$conta" ]] || {
    usage
    exit 1
  }
}

check_tools() {
  local tool
  for tool in terraform aws gh; do
    command -v "$tool" >/dev/null || die "'$tool' não encontrado no PATH"
  done
}

# Valida accounts/<conta>/ e exporta AWS_PROFILE. Define: account_id, region, bucket.
load_account() {
  local dir="$repo_root/accounts/$conta" f
  [[ -d "$dir" ]] || die "accounts/$conta/ não existe. Crie a partir de accounts/example/."
  for f in account.env account.tfvars backend.hcl; do
    [[ -f "$dir/$f" ]] || die "falta accounts/$conta/$f (veja accounts/example/)"
  done

  local profile account_name expected_bucket
  profile="$(read_env AWS_PROFILE "$dir/account.env")"
  account_name="$(read_hcl account_name "$dir/account.tfvars")"
  account_id="$(read_hcl account_id "$dir/account.tfvars")"
  region="$(read_hcl region "$dir/account.tfvars")"
  bucket="$(read_hcl bucket "$dir/backend.hcl")"

  [[ -n "$profile" ]] || die "AWS_PROFILE vazio em accounts/$conta/account.env"
  [[ -n "$account_id" && -n "$region" && -n "$bucket" ]] ||
    die "account_id, region (account.tfvars) e bucket (backend.hcl) são obrigatórios"
  [[ "$account_id" != "$EXAMPLE_ACCOUNT_ID" ]] ||
    die "accounts/$conta/account.tfvars ainda tem o account_id de exemplo ($EXAMPLE_ACCOUNT_ID)"
  [[ "$account_name" == "$conta" ]] ||
    die "account_name em account.tfvars ('$account_name') deve ser igual ao nome da pasta ('$conta')"

  expected_bucket="guetto-tfstate-${account_id}-${region}-an"
  [[ "$bucket" == "$expected_bucket" ]] ||
    die "backend.hcl aponta para '$bucket', mas o bootstrap cria '$expected_bucket'"

  export AWS_PROFILE="$profile"
}

check_credentials() {
  log "Conferindo credenciais (profile $AWS_PROFILE)"
  aws configure list-profiles | tr -d '\r' | grep -qxF "$AWS_PROFILE" ||
    die "profile '$AWS_PROFILE' não existe neste ambiente (rodando no WSL em vez do Git Bash?)"

  local caller
  caller="$(aws sts get-caller-identity --query Account --output text | tr -d '\r')" ||
    die "falha ao autenticar com o profile $AWS_PROFILE"
  [[ "$caller" == "$account_id" ]] ||
    die "o profile $AWS_PROFILE pertence à conta $caller, mas account.tfvars diz $account_id"

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    GITHUB_TOKEN="$(gh auth token 2>/dev/null)" || die "defina GITHUB_TOKEN ou rode 'gh auth login'"
    export GITHUB_TOKEN
  fi
}

# 0 = bucket existe; 1 = não existe; qualquer outro erro (ex.: 403) aborta.
bucket_exists() {
  local err
  if err="$(aws s3api head-bucket --bucket "$bucket" 2>&1 >/dev/null)"; then
    return 0
  fi
  if grep -q '(404)' <<<"$err"; then
    return 1
  fi
  die "não foi possível verificar o bucket $bucket: $err"
}

# Retorna 0 se aplicou ou não havia mudanças; 1 se só planejou (--plan).
plan_and_apply() {
  local rc=0 answer
  tf plan -input=false -var-file="../accounts/$conta/account.tfvars" \
    -detailed-exitcode -out="$plan_file" || rc=$?
  case "$rc" in
    0)
      log "Nenhuma mudança necessária."
      return 0
      ;;
    2) ;; # há mudanças
    *) die "terraform plan falhou" ;;
  esac

  if "$plan_only"; then
    log "--plan: nada foi aplicado."
    return 1
  fi

  read -r -p $'\nAplicar este plano? [s/N] ' answer
  [[ "$answer" =~ ^[sS]$ ]] || die "cancelado pelo usuário; nada foi aplicado"
  tf apply -input=false "$plan_file"
}

run_first_time() {
  log "Bucket $bucket não existe: primeira execução nesta conta (backend local temporário)"
  cat >"$override_file" <<'EOF'
# Temporário, gerado por scripts/bootstrap.sh (ignorado pelo Git). Substitui o backend "s3" de versions.tf.
terraform {
  backend "local" {}
}
EOF
  tf init -input=false -reconfigure
  plan_and_apply || return 0 # --plan: para aqui

  rm -f "$override_file"
  log "Migrando o state para s3://$bucket/00-bootstrap/"
  tf init -input=false -migrate-state -force-copy -backend-config="../accounts/$conta/backend.hcl"
  tf state list >/dev/null || die "state não pôde ser lido do S3 após a migração; state local preservado"
  rm -f "$layer_dir/terraform.tfstate" "$layer_dir/terraform.tfstate.backup"
}

run_existing() {
  # Um state local aqui indica execução anterior interrompida entre o apply e a migração.
  # Não migramos automaticamente: -force-copy poderia sobrescrever um state mais novo no S3.
  if [[ -s "$layer_dir/terraform.tfstate" ]]; then
    die "existe 00-bootstrap/terraform.tfstate local (execução anterior interrompida?).
Confira e migre manualmente:
  terraform -chdir=00-bootstrap init -migrate-state -backend-config=../accounts/$conta/backend.hcl"
  fi
  log "Bucket $bucket existe: usando o backend S3"
  tf init -input=false -reconfigure -backend-config="../accounts/$conta/backend.hcl"
  plan_and_apply || true
}

main() {
  parse_args "$@"
  check_tools
  load_account
  check_credentials

  if bucket_exists; then
    run_existing
  else
    run_first_time
  fi

  if ! "$plan_only"; then
    log "Outputs"
    tf output
  fi
}

main "$@"
