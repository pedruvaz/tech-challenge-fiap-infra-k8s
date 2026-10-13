variable "github_repositories" {
  description = <<-EOT
    Repositórios autorizados a assumir as roles de CI, no formato OWNER/REPO.

    Precisa listar os quatro repositórios da entrega mais o frontend: cada um
    tem pipeline próprio e todos autenticam por OIDC nesta mesma conta.
  EOT
  type        = list(string)
  default = [
    "pedruvaz/tech-challenge-fiap-infra-k8s",
    "pedruvaz/tech-challenge-fiap-infra-db",
    "pedruvaz/tech-challenge-fiap-lambda-auth",
    "pedruvaz/tech-challenge-fiap-app-oficina",
    "pedruvaz/tech-challenge-fiap",
    "Guilherme-silva-santos/tech-challenge-fiap-front",
  ]
}

variable "github_repositories_immutable" {
  description = <<-EOT
    Os mesmos repositórios no formato imutável que o GitHub usa no claim `sub`
    de repositórios criados recentemente: OWNER@ID/REPO@ID.

    Os IDs numéricos são estáveis por design (sobrevivem a rename) e saem de
    `gh api repos/OWNER/REPO/actions/oidc/customization/sub`, campo
    `sub_claim_prefix`.

    O match do IAM é literal: um repositório que emite o `sub` imutável e só
    está listado no formato clássico recebe "Not authorized to perform
    sts:AssumeRoleWithWebIdentity". Os quatro repositórios desta entrega foram
    criados em 2026 e emitem este formato — por isso aparecem nas duas listas.
  EOT
  type        = list(string)
  default = [
    "pedruvaz@212736700/tech-challenge-fiap-infra-k8s@1416885703",
    "pedruvaz@212736700/tech-challenge-fiap-infra-db@1416885783",
    "pedruvaz@212736700/tech-challenge-fiap-lambda-auth@1416885905",
    "pedruvaz@212736700/tech-challenge-fiap-app-oficina@1416885980",
    "Guilherme-silva-santos@82386781/tech-challenge-fiap-front@1349046005",
  ]
}

variable "aws_region" {
  description = "Região da AWS onde os recursos serão criados."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo e tag aplicados aos recursos. Também é o nome do repositório ECR."
  type        = string
  default     = "tech-challenge-fiap"
}

variable "github_allowed_subjects" {
  description = <<-EOT
    Padrões de claim `sub` do token OIDC autorizados, relativos ao repositório
    definido em `github_repository`.

    O default (`*`) libera qualquer branch, tag e pull request — é o que faz
    sentido enquanto o trabalho está em andamento e o CI roda em PRs.

    Depois da entrega, dá para apertar para apenas a branch principal:
      github_allowed_subjects = ["ref:refs/heads/main"]
  EOT
  type        = list(string)
  default     = ["*"]
}

variable "eks_cluster_name" {
  description = <<-EOT
    Nome do cluster EKS que a stack `cluster/` vai criar.

    Usado aqui só para escopar a permissão `eks:DescribeCluster` da role de
    deploy. O cluster não precisa existir ainda — uma policy do IAM pode
    referenciar um ARN futuro sem erro.
  EOT
  type        = string
  default     = "tech-challenge"
}

variable "ecr_keep_last_images" {
  description = "Quantas imagens com tag manter no ECR antes de expirar as mais antigas."
  type        = number
  default     = 10
}

variable "github_terraform_repositories" {
  description = <<-EOT
    Repositórios autorizados a assumir a role de provisionamento, nos dois
    formatos de `sub` (ver `github_repositories_immutable`).

    Só os repositórios de infraestrutura entram aqui. O `app-oficina` fica de
    fora de propósito: ele faz deploy, não provisiona.
  EOT
  type        = list(string)
  default = [
    "pedruvaz/tech-challenge-fiap-infra-k8s",
    "pedruvaz/tech-challenge-fiap-infra-db",
    "pedruvaz/tech-challenge-fiap-lambda-auth",
    "pedruvaz@212736700/tech-challenge-fiap-infra-k8s@1416885703",
    "pedruvaz@212736700/tech-challenge-fiap-infra-db@1416885783",
    "pedruvaz@212736700/tech-challenge-fiap-lambda-auth@1416885905",
  ]
}
