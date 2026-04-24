output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "cluster_id" {
  description = "ID of the EKS cluster."
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS cluster API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID for the EKS control plane."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes."
  value       = aws_security_group.nodes.id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role used by the EKS cluster."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role used by EKS worker nodes."
  value       = aws_iam_role.nodes.arn
}

output "node_iam_role_name" {
  description = "Name of the IAM role used by EKS worker nodes."
  value       = aws_iam_role.nodes.name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA."
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)."
  value       = var.enable_irsa ? local.oidc_issuer_url : null
}

output "kubeconfig_command" {
  description = "AWS CLI command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}
