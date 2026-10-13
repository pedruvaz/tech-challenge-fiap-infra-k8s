# Setup inicial da conta AWS

Runbook do **primeiro** provisionamento, numa conta AWS vazia. Roda uma vez. Depois
disso tudo acontece pelos pipelines, e ninguém precisa de credencial da AWS na máquina.

Quem já tem o ambiente de pé não precisa deste documento.

---

## O ovo e a galinha

Os pipelines autenticam por OIDC, assumindo roles IAM. Essas roles são criadas pela
stack `terraform/base`. Mas o `base` guarda o state num bucket S3 que também não
existe ainda, e precisa de credencial para o primeiro `apply`.

Ou seja, três coisas precisam existir **antes** do primeiro pipeline, e só podem ser
criadas à mão:

1. o bucket de state;
2. a stack `base` aplicada (que cria OIDC provider, as duas roles e o ECR);
3. os secrets e variables nos quatro repositórios do GitHub.

A partir daí, a cadeia roda sozinha.

---

## 0. Ferramentas

```bash
brew install awscli terraform
aws --version && terraform version
```

## 1. Conta AWS e credencial

Crie a conta, e nela um usuário IAM com `AdministratorAccess` — **não use a conta root
para o dia a dia**. Gere uma access key para esse usuário e configure:

```bash
aws configure
# Default region name: us-east-1
```

Confirme, e **guarde o account ID** que aparece:

```bash
aws sts get-caller-identity
```

## 2. Decidir o nome do bucket de state

> ⚠️ **Leia antes de continuar.**

O bucket está **hardcoded** em quatro arquivos, com um account ID embutido:

```
tf-state-tech-challenge-fiap-679084116359
```

- `terraform/base/versions.tf`
- `terraform/cluster/versions.tf`
- `infra-db` → `terraform/versions.tf`
- `lambda-auth` → `terraform/versions.tf`

**Se o account ID da sua conta for outro**, os quatro precisam ser atualizados, cada um
num PR no seu repositório, antes de qualquer `init`. Nome de bucket S3 é global: não dá
para duas contas usarem o mesmo.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="tf-state-tech-challenge-fiap-${ACCOUNT_ID}"
echo "$BUCKET"
```

## 3. Criar o bucket

```bash
aws s3api create-bucket --bucket "$BUCKET" --region us-east-1

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

Versionamento não é opcional: é o que permite recuperar um state corrompido por um
`apply` interrompido.

## 4. Aplicar a stack `base` à mão

É o único `apply` feito com credencial de pessoa. Ele cria o OIDC provider, as duas
roles, o ECR e o bucket do frontend.

```bash
cd terraform/base
terraform init
terraform plan      # confira antes de aplicar
terraform apply
```

Guarde os outputs:

```bash
terraform output -json > /tmp/base-outputs.json
terraform output
```

## 5. Configurar os repositórios do GitHub

Com os outputs do passo anterior:

```bash
cd terraform/base
TERRAFORM_ROLE=$(terraform output -raw github_terraform_role_arn)
DEPLOY_ROLE=$(terraform output -raw github_actions_role_arn)
FRONTEND_URL=$(terraform output -raw frontend_website_endpoint)

OWNER=pedruvaz   # ajuste se os repositórios mudarem de dono

for r in infra-k8s infra-db lambda-auth; do
  gh secret set AWS_TERRAFORM_ROLE_ARN --repo "$OWNER/tech-challenge-fiap-$r" --body "$TERRAFORM_ROLE"
  gh variable set AWS_REGION           --repo "$OWNER/tech-challenge-fiap-$r" --body "us-east-1"
done

APP="$OWNER/tech-challenge-fiap-app-oficina"
gh secret   set AWS_DEPLOY_ROLE_ARN --repo "$APP" --body "$DEPLOY_ROLE"
gh variable set AWS_REGION          --repo "$APP" --body "us-east-1"
gh variable set ECR_REPOSITORY      --repo "$APP" --body "tech-challenge-fiap"
gh variable set EKS_CLUSTER_NAME    --repo "$APP" --body "tech-challenge"
gh variable set API_SECRET_NAME     --repo "$APP" --body "tech-challenge-fiap/api"
gh variable set FRONTEND_URL        --repo "$APP" --body "$FRONTEND_URL"
```

Resumo do que cada repositório precisa:

| Repositório | Secrets | Variables |
|---|---|---|
| `infra-k8s` | `AWS_TERRAFORM_ROLE_ARN` | `AWS_REGION` |
| `infra-db` | `AWS_TERRAFORM_ROLE_ARN` | `AWS_REGION` |
| `lambda-auth` | `AWS_TERRAFORM_ROLE_ARN` | `AWS_REGION` |
| `app-oficina` | `AWS_DEPLOY_ROLE_ARN` | `AWS_REGION`, `ECR_REPOSITORY`, `EKS_CLUSTER_NAME`, `API_SECRET_NAME`, `FRONTEND_URL` |

## 6. Rodar a cadeia, nesta ordem

```
base (feito à mão no passo 4)
  └─> cluster     infra-k8s    VPC + EKS + metrics-server
        └─> db    infra-db     RDS + Secrets Manager
              └─> lambda-auth  função de autenticação
                    └─> app-oficina   API no cluster
```

A ordem não é negociável: cada stack lê os outputs da anterior por
`terraform_remote_state`. O `cluster` demora ~20 min por conta do EKS.

Depois do `cluster`, confirme o acesso:

```bash
aws eks update-kubeconfig --name tech-challenge --region us-east-1
kubectl get nodes
```

---

## Custo

Com tudo de pé, rodando 24/7, a ordem de grandeza é **US$ 130–150/mês**:

| Item | Aprox./mês |
|---|---|
| Control plane do EKS | US$ 73 |
| NAT Gateway | US$ 32 |
| NLB | US$ 16 |
| RDS `db.t4g.micro` | US$ 15 |
| Nós EC2, ECR, S3, logs | o resto |

O control plane cobra por hora **mesmo sem nenhum pod rodando**. Fora das sessões de
trabalho, derrube na ordem inversa:

```bash
# lambda-auth, depois db, depois cluster — nunca o contrário
terraform destroy
```

Não derrube o `base`: ele guarda o OIDC e as roles, custa praticamente nada, e
recriá-lo obriga a reconfigurar todos os secrets.

## Armadilhas conhecidas

- **`terraform destroy` do `cluster` falha** se ainda houver Service `LoadBalancer` no
  namespace. Apague os Services antes, senão o NLB segura a VPC.
- **O segredo do banco fica em quarentena.** Se o `infra-db` for destruído e recriado,
  o Secrets Manager pode recusar o nome por até 30 dias, a menos que
  `recovery_window_in_days` seja 0.
- **Access key no GitHub é desnecessária.** Se alguém pedir, o OIDC está quebrado —
  conserte o OIDC em vez de contornar com chave estática.
