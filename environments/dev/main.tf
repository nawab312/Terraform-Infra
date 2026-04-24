# ─────────────────────────────────────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name         = "${var.project_name}-${var.environment}"
  cluster_name = "${var.project_name}-${var.environment}-eks"

  # Common tags applied to every resource
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: VPC
# Creates: 3-tier VPC (public/private/isolated) across 2 AZs
# ─────────────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  name = local.name

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  # Public subnets: for ALB and NAT Gateways
  # /24 = 251 usable IPs (plenty for ALB nodes and NAT GW)
  public_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 1), # 10.0.1.0/24 in AZ-a
    cidrsubnet(var.vpc_cidr, 8, 2), # 10.0.2.0/24 in AZ-b
  ]

  # Private subnets: for EKS nodes
  # /19 = 8187 usable IPs (nodes + pods, EKS needs many IPs via VPC CNI)
  private_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 3, 2), # 10.0.32.0/19 in AZ-a  (8187 IPs)
    cidrsubnet(var.vpc_cidr, 3, 3), # 10.0.64.0/19 in AZ-b  (8187 IPs)
  ]

  # Isolated subnets: for databases (no internet access)
  # Empty for now — add when deploying RDS
  isolated_subnet_cidrs = []

  enable_nat_gateway = true
  single_nat_gateway = true # Cost optimization for dev (loses HA — fine for lab)

  # Tag subnets for AWS Load Balancer Controller auto-discovery
  eks_cluster_name = local.cluster_name

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: EKS
# Creates: EKS cluster + managed node group + OIDC provider for IRSA
# ─────────────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  # API server access
  cluster_endpoint_public_access       = true  # Need this for kubectl from laptop
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Node groups
  node_groups = {
    general = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      disk_size      = 20
      labels         = {}
      taints         = []
    }
  }

  # Enable IRSA (required for pods to access AWS services)
  enable_irsa = true

  # Control plane logging (all types for dev)
  enable_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.tags
}
