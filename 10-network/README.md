# 10-network

Camada **efêmera**: sobe no `up` e desce no `down`. Cria a rede onde o EKS vai rodar (ADR-0013).
Consome o módulo `vpc` da biblioteca [`terraform-aws-modules`](https://github.com/vitorfprado/terraform-aws-modules)
na tag `v1.1.0` (ADR-0010).

## O que esta camada cria

```
VPC 10.20.0.0/16 (3 AZs, escolhidas por ID)
├── públicas /24 × 3  ── route table pública ── 0.0.0.0/0 → Internet Gateway
│     └── NAT Gateway (único) + Elastic IP
└── privadas /19 × 3  ── route table por AZ ─── 0.0.0.0/0 → NAT Gateway
                                             └─ S3 (prefix list) → Gateway Endpoint (gratuito)
SSM /guetto/network/*  → contrato lido pelo 20-cluster
```

| Recurso | Para quê | Custo |
|---|---|---|
| VPC, subnets, route tables, Internet Gateway | Rede base. Privadas para nós/pods; públicas só para LB e NAT | Gratuito |
| NAT Gateway + Elastic IP | Saída à internet das subnets privadas (pull de imagens, APIs AWS) | **~US$ 0,045/h + por GB** — o item que cobra nesta camada |
| S3 Gateway Endpoint | Tráfego ao S3 (inclusive camadas de imagens do ECR) sem passar pelo NAT | Gratuito |
| 4 parâmetros SSM (`/guetto/network/…`) | Contrato com o `20-cluster`: `vpc-id`, `vpc-cidr`, `private-subnet-ids`, `public-subnet-ids` (ADR-0015) | Gratuito (standard) |

### Detalhes que importam

- **AZs por ID:** o EKS rejeita subnets em `use1-az3` (us-east-1), `usw1-az2` e `cac1-az3`, e o mapeamento nome → ID
  muda por conta. A camada exclui esses IDs no data source `aws_availability_zones` e passa a lista ao módulo.
  [EKS — requisitos de rede](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html).
- **Sem IP público automático** nas subnets públicas: só NAT e load balancers vivem lá.
- **Tags para o AWS Load Balancer Controller:** `kubernetes.io/role/elb=1` (públicas) e
  `kubernetes.io/role/internal-elb=1` (privadas).
- Todos os recursos levam `ephemeral=true` (`default_tags`), usado pelo reaper e pela verificação de órfãos.

## Configuração

Sem `.tfvars` por conta: o plano de endereçamento está nos defaults de [variables.tf](variables.tf). A conta vem de
variáveis de ambiente (ADR-0015): `TF_VAR_account_id` e o backend (`-backend-config`), preenchidos pelos scripts
a partir de `accounts/<conta>/` (local) ou do GitHub Environment (CI).

Operação normal: `scripts/up.sh` / `scripts/down.sh` (em construção).
