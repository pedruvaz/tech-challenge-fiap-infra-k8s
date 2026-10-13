# Contrato desta stack com as demais.
#
# `infra-db` e `lambda-auth` leem estes valores via `terraform_remote_state`.
# Mudar nome ou tipo de um output aqui quebra o apply das outras stacks, então
# trate-os como API pública: adicione à vontade, renomeie com cuidado.

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do control plane."
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Comando para apontar o kubectl local para este cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  description = "Repetido da stack `base` para facilitar — é o valor do `image:` dos manifestos."
  value       = data.terraform_remote_state.base.outputs.ecr_repository_url
}

# --- Consumidos pela stack `infra-db` -----------------------------------

output "vpc_id" {
  description = "VPC onde o RDS e a Lambda devem nascer."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Subnets privadas — subnet group do RDS e VPC config da Lambda."
  value       = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  description = "CIDR da VPC."
  value       = module.vpc.vpc_cidr_block
}

output "cluster_primary_security_group_id" {
  description = <<-EOT
    Security group primário do cluster. No EKS Auto Mode é ele que as ENIs dos
    pods recebem, então é este o SG que o ingress do RDS precisa liberar.
  EOT
  value       = module.eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "SG dos nodes. Alternativa ao primário caso os pods deixem de alcançar o banco."
  value       = module.eks.node_security_group_id
}

output "aws_region" {
  description = "Região onde a stack foi aplicada — evita divergência entre as stacks."
  value       = var.aws_region
}

output "project_name" {
  description = "Prefixo comum de nomes e tags."
  value       = var.project_name
}
