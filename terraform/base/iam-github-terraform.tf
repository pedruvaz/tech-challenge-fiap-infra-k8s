# Role de *provisionamento*, separada da role de deploy.
#
# Por que duas roles: a role `github_actions` existente é deliberadamente
# estreita — publica imagem no ECR, descreve o cluster e lê um segredo. Criar
# VPC, EKS e RDS exige permissão de outra ordem de grandeza, e dar isso ao
# pipeline da aplicação significaria que um PR no código da API passa a poder
# destruir o cluster. Separando, o blast radius de cada pipeline é o seu.
#
# Quem assume esta role: apenas os repositórios de infraestrutura
# (`infra-k8s`, `infra-db`) e o da Lambda, que também provisiona a própria
# função. O `app-oficina` continua só com a role de deploy.

data "aws_iam_policy_document" "github_terraform_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for r in var.github_terraform_repositories : [
          for s in var.github_allowed_subjects : "repo:${r}:${s}"
        ]
      ])
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name        = "${var.project_name}-github-terraform"
  description = "Assumida pelos repositórios de infraestrutura para rodar terraform plan/apply."

  assume_role_policy = data.aws_iam_policy_document.github_terraform_assume_role.json
}

# PowerUserAccess + IAM: o Terraform destas stacks cria VPC, EKS, RDS, Secrets
# Manager e Lambda, e também as roles e os instance profiles que esses serviços
# exigem — o que o PowerUser sozinho não cobre.
#
# É uma permissão ampla e assumida como tal: o controle de quem a usa está no
# trust acima (só os repositórios de infra, e só via OIDC) e na proteção da
# branch `main`, não no recorte da policy. Apertar isto para a lista exata de
# ações é trabalho de produção; aqui seria uma caça a AccessDenied a cada
# recurso novo, sem ganho real de segurança para uma conta de estudo.
resource "aws_iam_role_policy_attachment" "github_terraform_poweruser" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "github_terraform_iam" {
  statement {
    sid    = "ManageServiceRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:CreateServiceLinkedRole",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_terraform_iam" {
  name        = "${var.project_name}-github-terraform-iam"
  description = "Complementa o PowerUserAccess com o IAM necessário para EKS, RDS e Lambda."
  policy      = data.aws_iam_policy_document.github_terraform_iam.json
}

resource "aws_iam_role_policy_attachment" "github_terraform_iam" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform_iam.arn
}
