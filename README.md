# tech-challenge-fiap-infra-k8s

Infraestrutura base e cluster Kubernetes do Tech Challenge, em Terraform.

É o **primeiro** repositório da cadeia de deploy: os outros três leem os
outputs daqui via `terraform_remote_state`. Nada sobe antes deste.

## Propósito

Provisiona, numa conta AWS:

- **VPC** com subnets públicas e privadas em 2 AZs, NAT e rotas.
- **Cluster EKS** em Auto Mode, com escalabilidade de nós gerenciada pela AWS.
- **metrics-server**, sem o qual o HPA da aplicação não funciona.
- **ECR** para a imagem da API.
- **OIDC do GitHub Actions** e as duas roles que os quatro repositórios
  assumem — sem access key guardada em secret.

Não provisiona o banco (fica em `infra-db`) nem a função de autenticação
(fica em `lambda-auth`).

## Tecnologias

Terraform ~> 1.13 · AWS Provider ~> 6.0 · módulos `terraform-aws-modules/vpc`
e `terraform-aws-modules/eks` · Helm provider · GitHub Actions com OIDC.

## Arquitetura deste repositório

```
                    ┌──────────────────────────────┐
                    │  stack  base/                │
                    │  ECR · OIDC provider         │
                    │  role deploy · role terraform│
                    └───────────────┬──────────────┘
                                    │ terraform_remote_state
                                    ▼
                    ┌──────────────────────────────┐
   VPC 10.0.0.0/16  │  stack  cluster/             │
   2 AZs            │  VPC · subnets · NAT         │
                    │  EKS Auto Mode               │
                    │  metrics-server (Helm)       │
                    └───────────────┬──────────────┘
                                    │ outputs
                 ┌──────────────────┼──────────────────┐
                 ▼                  ▼                  ▼
            infra-db           lambda-auth         app-oficina
     vpc_id, subnets,      subnets privadas     cluster_name, ECR
     primary SG            (acesso ao RDS)
```

### Outputs que as outras stacks consomem

| Output | Quem lê | Para quê |
|---|---|---|
| `vpc_id` | infra-db, lambda-auth | criar SG e colocar a Lambda na VPC |
| `private_subnet_ids` | infra-db, lambda-auth | subnet group do RDS, VPC config da Lambda |
| `cluster_primary_security_group_id` | infra-db | liberar o ingress 5432 só para os pods |
| `cluster_name` | app-oficina | `aws eks update-kubeconfig` no deploy |
| `ecr_repository_url` | app-oficina | destino do `docker push` |

Esses nomes são contrato. Renomear um deles quebra o `apply` dos outros
repositórios — trate `outputs.tf` como API pública.

## Execução

### T0 — bucket de state (uma vez, à mão)

O backend S3 não pode criar o próprio bucket, então ele nasce fora do
Terraform:

```bash
aws s3api create-bucket \
  --bucket tf-state-tech-challenge-fiap-<ACCOUNT_ID> \
  --region us-east-1
aws s3api put-bucket-versioning \
  --bucket tf-state-tech-challenge-fiap-<ACCOUNT_ID> \
  --versioning-configuration Status=Enabled
```

O nome está literal em `versions.tf` das duas stacks (blocos `backend` não
aceitam variável) — troque nos dois antes do primeiro `init`.

### T1 — stack `base`

```bash
cd terraform/base
cp terraform.tfvars.example terraform.tfvars   # ajuste os repositórios
terraform init
terraform apply
```

Guarde dois outputs:

```bash
terraform output github_actions_role_arn     # secret AWS_DEPLOY_ROLE_ARN
terraform output github_terraform_role_arn   # secret AWS_TERRAFORM_ROLE_ARN
```

### T2 — stack `cluster`

```bash
cd ../cluster
terraform init
terraform apply          # ~15 min: o control plane do EKS demora
$(terraform output -raw configure_kubectl)
kubectl get nodes
```

### Destruir

Na ordem inversa, e **depois** de destruir o `infra-db` (o RDS vive nas
subnets desta VPC e segura o destroy):

```bash
cd terraform/cluster && terraform destroy
cd ../base            && terraform destroy
```

## CI/CD

`.github/workflows/terraform.yml`:

| Gatilho | O que roda |
|---|---|
| Pull request para `main`/`dev` | `fmt`, `validate` e `plan` das duas stacks; o plan vira comentário no PR |
| Push em `main` | `apply` de `base` e depois `cluster`, em sequência |

Configure antes do primeiro push:

- Secret `AWS_TERRAFORM_ROLE_ARN` — output `github_terraform_role_arn`.
- Variable `AWS_REGION` — ex.: `us-east-1`.

A branch `main` é protegida: merge só via Pull Request.

### Por que não há ambiente de homologação aqui

Homolog e produção se separam na camada da aplicação, por **namespace do
Kubernetes** (ver `app-oficina`), não duplicando a infraestrutura. Um segundo
workspace do Terraform nesta conta criaria um segundo cluster EKS e um segundo
RDS: os nomes colidiriam (role, ECR e cluster derivam de `project_name`, que é
fixo) e o custo dobraria. O cluster é compartilhado; o isolamento é por
namespace.

### Duas roles, de propósito

| Role | Quem assume | Pode |
|---|---|---|
| `…-github-actions` | os 4 repos + frontend | push no ECR, `eks:DescribeCluster`, ler o segredo da API, sync no S3 |
| `…-github-terraform` | só os 3 repos de infra | PowerUser + IAM — provisionar VPC, EKS, RDS, Lambda |

O pipeline da aplicação nunca recebe permissão para destruir o cluster. O
controle de quem usa a role ampla está no trust (só esses repositórios, só via
OIDC) e na proteção da `main`.

### Formato do `sub` no OIDC

O GitHub emite o claim `sub` em dois formatos: clássico (`OWNER/REPO`) para
repositórios antigos e imutável (`OWNER@ID/REPO@ID`) para os criados
recentemente. O match do IAM é **literal** — um repositório listado só no
formato errado falha com `Not authorized to perform
sts:AssumeRoleWithWebIdentity`. Por isso os quatro repositórios aparecem nas
duas listas (`github_repositories` e `github_repositories_immutable`).

Para conferir o formato de um repositório:

```bash
gh api repos/OWNER/REPO/actions/oidc/customization/sub
```

## Repositórios da entrega

| Repositório | Papel |
|---|---|
| [infra-k8s](https://github.com/pedruvaz/tech-challenge-fiap-infra-k8s) | **este** — VPC, EKS, ECR, OIDC |
| [infra-db](https://github.com/pedruvaz/tech-challenge-fiap-infra-db) | RDS PostgreSQL e Secrets Manager |
| [lambda-auth](https://github.com/pedruvaz/tech-challenge-fiap-lambda-auth) | autenticação por CPF, emissão do JWT |
| [app-oficina](https://github.com/pedruvaz/tech-challenge-fiap-app-oficina) | API da oficina no EKS |
