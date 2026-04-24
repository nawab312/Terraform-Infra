# ─────────────────────────────────────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # How many AZs to deploy into
  az_count = length(var.availability_zones)

  # How many NAT Gateways to create
  # single_nat_gateway = true  → 1 NAT (cost optimization for dev)
  # single_nat_gateway = false → 1 NAT per AZ (HA for production)
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  # EKS subnet tags (needed for AWS Load Balancer Controller)
  eks_public_subnet_tags = var.eks_cluster_name != "" ? {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  } : {}

  eks_private_subnet_tags = var.eks_cluster_name != "" ? {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  } : {}

  # Common tags applied to every resource
  common_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    Environment = var.name
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${var.name}-vpc"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# SUBNETS — PUBLIC (load balancers, NAT Gateways)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, local.eks_public_subnet_tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# SUBNETS — PRIVATE (EKS nodes, application servers)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, local.eks_private_subnet_tags, {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# SUBNETS — ISOLATED (databases, no internet access)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "isolated" {
  count = length(var.isolated_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.isolated_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.name}-isolated-${var.availability_zones[count.index]}"
    Tier = "isolated"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERNET GATEWAY
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-igw"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# ELASTIC IPs FOR NAT GATEWAYS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  # Ensure IGW exists before creating EIP
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-eip-${var.availability_zones[count.index]}"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT GATEWAYS (in public subnets, for private subnet outbound internet)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  # Place NAT Gateway in the public subnet
  subnet_id = aws_subnet.public[count.index].id

  # Assign an Elastic IP
  allocation_id = aws_eip.nat[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-${var.availability_zones[count.index]}"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# ROUTE TABLES — PUBLIC
# Routes: VPC local + 0.0.0.0/0 → Internet Gateway
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────────────────────────────────────
# ROUTE TABLES — PRIVATE
# Routes: VPC local + 0.0.0.0/0 → NAT Gateway
# One route table per AZ (each points to its own NAT for HA)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-rt-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(var.private_subnet_cidrs) : 0

  route_table_id = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # With single NAT → all private subnets route to NAT in AZ-a
  # With multi NAT  → each private subnet routes to its own AZ's NAT
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id

  depends_on = [aws_route_table.private]
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─────────────────────────────────────────────────────────────────────────────
# ROUTE TABLES — ISOLATED
# Routes: VPC local ONLY (no internet access — maximum isolation for databases)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_route_table" "isolated" {
  count = length(var.isolated_subnet_cidrs) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  # Intentionally no 0.0.0.0/0 route — isolated subnets have NO internet access

  tags = merge(local.common_tags, {
    Name = "${var.name}-isolated-rt"
  })
}

resource "aws_route_table_association" "isolated" {
  count = length(var.isolated_subnet_cidrs)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[0].id
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC ENDPOINTS — Free gateway endpoints for S3 and DynamoDB
# Avoids NAT Gateway charges for AWS API calls
# ─────────────────────────────────────────────────────────────────────────────

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Add to all private and isolated route tables
  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.isolated[*].id
  )

  tags = merge(local.common_tags, {
    Name = "${var.name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.isolated[*].id
  )

  tags = merge(local.common_tags, {
    Name = "${var.name}-dynamodb-endpoint"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC FLOW LOGS
# Logs all network traffic for security auditing and debugging
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = 7 # Keep 7 days for dev (increase for prod)

  lifecycle {
    ignore_changes = [name]
  }

  tags = local.common_tags
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-flow-log"
  })
}
