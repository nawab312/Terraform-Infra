variable "name" {
  description = "Name prefix for all VPC resources. Used in resource names and tags."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 20
    error_message = "Name must be between 1 and 20 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "Name must only contain lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a valid /16 to /20 range."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to deploy into. Minimum 2 for HA."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Must specify at least 2 availability zones for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. One per availability zone."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Must specify at least 2 public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes, application layer). One per AZ."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Must specify at least 2 private subnet CIDRs."
  }
}

variable "isolated_subnet_cidrs" {
  description = "CIDR blocks for isolated subnets (databases). No internet access. One per AZ."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateways for private subnet outbound internet access."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost optimization for dev). Set false for production HA."
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC. Required for EKS."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC. Required for EKS."
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "EKS cluster name. Used to tag subnets for ALB/ELB auto-discovery."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
