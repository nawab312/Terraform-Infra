# ─────────────────────────────────────────────────────────────────────────────
# REMOTE STATE BACKEND
#
# State is stored in S3 (versioned) and locked via DynamoDB.
# Run scripts/bootstrap.sh ONCE to create these resources.
#
# To migrate from local to remote state after bootstrap:
#   terraform init -migrate-state
# ─────────────────────────────────────────────────────────────────────────────

terraform {
    backend "s3" {
        bucket = "infra-lab-terraform-state-617438303535"
        key = "dev/terraform.tfstate"
        region = "us-east-1"
        dynamodb_table = "infra-lab-terraform-locks"
        encrypt = true 
    }
} 