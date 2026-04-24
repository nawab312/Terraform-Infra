# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# TLS certificate for OIDC (used for IRSA)
data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ─────────────────────────────────────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClusterName = var.cluster_name
  })

  # OIDC issuer URL without https:// prefix (used in IAM policies)
  oidc_issuer_url = var.enable_irsa ? replace(
    aws_eks_cluster.main.identity[0].oidc[0].issuer,
    "https://",
    ""
  ) : ""
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — CLUSTER ROLE
# The EKS control plane assumes this role to manage AWS resources
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# AWS managed policies for the cluster role
resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUP — CLUSTER (control plane)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS cluster control plane security group."
  vpc_id      = var.vpc_id

  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic."
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nodes to communicate with the control plane
resource "aws_security_group_rule" "cluster_ingress_nodes_443" {
  description              = "Allow nodes to communicate with control plane (HTTPS)."
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUP — NODES
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"
  description = "EKS worker node security group."
  vpc_id      = var.vpc_id

  # Allow all node-to-node communication
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all inbound traffic between nodes."
  }

  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic."
  }

  tags = merge(local.common_tags, {
    Name                                          = "${var.cluster_name}-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}"   = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Separate rules for control plane → node communication
resource "aws_security_group_rule" "nodes_ingress_cluster_443" {
  description = "Allow control plane HTTPS to nodes"
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.nodes.id 
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "nodes_ingress_cluster_kubelet" {
  description = "Allow control plane to communicate with nodes (kubelet)"
  type = "ingress"
  from_port = 1025
  to_port = 65535
  protocol = "tcp"
  security_group_id = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Log Group for EKS control plane logs
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7 # Increase for production

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS CLUSTER
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # VPC configuration
  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  # Enable control plane logging
  enabled_cluster_log_types = var.enable_cluster_log_types

  # Encrypt secrets with KMS
  # encryption_config {
  #   provider {
  #     key_arn = aws_kms_key.eks.arn
  #   }
  #   resources = ["secrets"]
  # }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS ADDONS
# Managed add-ons for DNS, networking, storage
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_addon" "main" {
  for_each = var.cluster_addons

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = each.key
  addon_version            = each.value.version != null ? each.value.version : null
  resolve_conflicts_on_update = each.value.resolve_conflicts

  depends_on = [
    aws_eks_node_group.main,
  ]

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC PROVIDER — For IRSA (IAM Roles for Service Accounts)
# Allows pods to assume IAM roles via service account annotations
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — NODE GROUP ROLE
# EC2 nodes assume this role to join the cluster and access AWS services
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# AWS managed policies for node role
resource "aws_iam_role_policy_attachment" "nodes_worker_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "nodes_cni_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "nodes_ecr_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "nodes_ebs_csi_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ─────────────────────────────────────────────────────────────────────────────
# MANAGED NODE GROUPS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids # Nodes always in private subnets

  # Instance configuration
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  # Scaling configuration
  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  # Update configuration (rolling updates)
  update_config {
    max_unavailable_percentage = 25 # At most 25% of nodes unavailable during updates
  }

  # Labels for workload placement
  labels = each.value.labels

  # Taints for dedicated node groups
  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_worker_policy,
    aws_iam_role_policy_attachment.nodes_cni_policy,
    aws_iam_role_policy_attachment.nodes_ecr_policy,
  ]

  # Ignore changes to desired_size (HPA/Cluster Autoscaler manages this)
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${each.key}"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS AUTH CONFIGMAP
# Controls which IAM users/roles can access the cluster
# ─────────────────────────────────────────────────────────────────────────────
# NOTE: In practice, use the EKS Access Entries API (newer, better) or
# the aws-auth ConfigMap. We leave this to the environment layer to configure
# per-team access via IAM Access Entries.
