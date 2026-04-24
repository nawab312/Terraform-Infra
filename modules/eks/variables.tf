variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_name))
    error_message = "Cluster name must start with a letter and contain only letters, numbers, and hyphens."
  }

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster. Use a supported version."
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^1\\.(2[0-9]|[3-9][0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format '1.XX' (e.g., 1.29)."
  }
}

variable "vpc_id" {
  description = "ID of the VPC to deploy EKS into."
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "Must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for EKS nodes. Must be in at least 2 AZs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Must provide at least 2 private subnet IDs for high availability."
  }
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for the EKS control plane endpoint (if public access enabled)."
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Map of node group configurations. Each key is the node group name."
  type = map(object({
    # Instance configuration
    instance_types = list(string)
    capacity_type  = string # ON_DEMAND or SPOT

    # Scaling
    min_size     = number
    max_size     = number
    desired_size = number

    # Disk
    disk_size = number # in GB

    # Labels and taints for workload placement
    labels = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE
    }))
  }))

  default = {
    general = {
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 20
      labels         = {}
      taints         = []
    }
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)
    ])
    error_message = "capacity_type must be 'ON_DEMAND' or 'SPOT'."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size
    ])
    error_message = "For each node group: min_size <= desired_size <= max_size."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS API endpoint. Restrict with public_access_cidrs."
  type        = bool
  default     = true # true for dev (need to reach cluster from laptop). false for prod.
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access the public EKS API endpoint. Restrict to your IP for security."
  type        = list(string)
  default     = ["0.0.0.0/0"] # Override with your specific IP in tfvars!

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "Must specify at least one CIDR for public access."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the EKS API endpoint from within the VPC."
  type        = bool
  default     = true
}

variable "enable_cluster_log_types" {
  description = "EKS control plane log types to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for log_type in var.enable_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (OIDC provider). Required for IRSA."
  type        = bool
  default     = true
}

variable "cluster_addons" {
  description = "Map of EKS cluster addons to enable."
  type = map(object({
    version               = string
    resolve_conflicts     = string # OVERWRITE or PRESERVE
  }))
  default = {
    coredns = {
      version           = null
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      version           = null
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      version           = null
      resolve_conflicts = "OVERWRITE"
    }
  }
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
