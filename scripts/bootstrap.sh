#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — One-time remote state infrastructure setup
#
# Run this ONCE before your first `terraform init`.
# Creates:
#   - S3 bucket (versioned, encrypted) for Terraform state
#   - DynamoDB table for state locking
#
# Usage: ./scripts/bootstrap.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

#--- Colours for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*";
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*";
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*";
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2;
}

#--- Prompt for Configuration ---
echo ""
echo "═══════════════════════════════════════════════════════"
echo "   Terraform Remote State Bootstrap"
echo "═══════════════════════════════════════════════════════"
echo ""

read -p "AWS Region (e.g., ap-south-1): " AWS_REGION
read -p "Project Name (used as prefix. e.g., infra-lab): " PROJECT_NAME
read -p "AWS Profile (Enter for default): " AWS_PROFILE_INPUT

if [[ -n "$AWS_PROFILE_INPUT" ]]; then
    export AWS_PROFILE="$AWS_PROFILE_INPUT"
    AWS_PROFILE_ARG="--profile $AWS_PROFILE_INPUT"
fi 

# Generate unique bucket name
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
LOCK_TABLE="${PROJECT_NAME}-terraform-locks"

echo ""
log_info "Will Create:"
echo " S3 Bucket: ${STATE_BUCKET}"
echo " Dynamo Table: ${LOCK_TABLE}"
echo " Region: ${AWS_REGION}"
echo ""

read -p "Proceed? (yes/no): " confirm

if [[ "${confirm,,}" != "yes" ]]; then 
    echo "Aborted"
    exit 0
fi

#--- Create S3 Bucket ---
log_info "Creating S3 Bucket: $STATE_BUCKET"

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then 
    log_warn "Bucket already exists: $STATE_BUCKET (skipping creation)"
else
    if [[ "$AWS_REGION" == "us-east-1" ]]; then 
        # us-east-1 doesn't accept LocationConstraint
        aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"
    else 
        aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    log_success "Bucket created: $STATE_BUCKET"
fi 

# Enable Versioning (Let us recover from state corruption)
log_info "Enable bucket versioning ..."
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" --versioning-configuration Status=Enabled
log_success "Versioning enabled"

# Enable server side encryption
log_info "Enabling bucket encryption (AES 256) ..."
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" --server-side-encryption-configuration file://encryption.json
log_success "Encryption enabled"

# Block all Public access
log_info "Blocking public access ..."
aws s3api put-public-access-block --bucket "$STATE_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
log_success "Public access blocked"

# Creating DynamoDB Table for state locking
log_info "Creatin DynamoDB lock table: $LOCK_TABLE"

if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null; then
    log_warn "DynamoDB Table already exists: $LOCK_TABLE (skipping creation)"
else 
    aws dynamodb create-table \
        --table-name "$LOCK_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"
    
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$AWS_REGION"
    log_success "DynamoDB Table created: $LOCK_TABLE"
fi 

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "  ${GREEN}Bootstrap complete!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Next: Update environments/dev/backend.tf with these values:"
echo ""
echo "  terraform {"
echo "    backend \"s3\" {"
echo "      bucket         = \"${STATE_BUCKET}\""
echo "      key            = \"dev/terraform.tfstate\""
echo "      region         = \"${AWS_REGION}\""
echo "      dynamodb_table = \"${LOCK_TABLE}\""
echo "      encrypt        = true"
echo "    }"
echo "  }"
echo ""
echo "Then:"
echo "  cd environments/dev"
echo "  cp terraform.tfvars.example terraform.tfvars"
echo "  # Edit terraform.tfvars with your values"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""