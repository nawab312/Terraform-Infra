output "region" {
  description = "AWS region where resources are deployed."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version."
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes)."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway public IPs (for firewall allowlisting)."
  value       = module.vpc.nat_gateway_public_ips
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN. Use this when creating IRSA IAM roles."
  value       = module.eks.oidc_provider_arn
}

output "node_iam_role_name" {
  description = "IAM role name for EKS nodes. Use for attaching additional policies."
  value       = module.eks.node_iam_role_name
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl after deploy."
  value       = module.eks.kubeconfig_command
}

# ─────────────────────────────────────────────────────────────────────────────
# AFTER DEPLOY — print these instructions
# ─────────────────────────────────────────────────────────────────────────────

output "next_steps" {
  description = "What to do after terraform apply completes."
  value       = <<-EOT

    ┌─────────────────────────────────────────────────────────────┐
    │ ✅ Infrastructure deployed!                                  │
    │                                                              │
    │ 1. Configure kubectl:                                        │
    │    ${module.eks.kubeconfig_command}
    │                                                              │
    │ 2. Verify nodes are ready:                                   │
    │    kubectl get nodes                                         │
    │                                                              │
    │ 3. When done practicing, destroy to avoid charges:           │
    │    terraform destroy                                         │
    │                                                              │
    │ Estimated cost: ~$0.43/day if left running                   │
    └─────────────────────────────────────────────────────────────┘

  EOT
}
