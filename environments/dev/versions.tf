terraform {
    required_version = ">= 1.6.0"
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = ">= 5.30.0, < 6.0.0"
      }
      tls = {
        source = "hashicorp/tls"
        version = ">= 4.0.0"
      }
    }
}

provider "aws" {
    region = var.region 

    # All resources created by this config get these default tag
    default_tags {
      tags = {
        Environment = var.environment 
        Project = var.project_name
        ManagedBy = "terraform"
        Owner = var.owner
      }
    }
}