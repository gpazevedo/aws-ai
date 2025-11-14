# =============================================================================
# Networking Resources (VPC)
# =============================================================================
# Creates VPC and related networking resources
# Enabled when: enable_eks = true OR create_vpc = true
# =============================================================================

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  count = local.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

# =============================================================================
# Public Subnets
# =============================================================================

resource "aws_subnet" "public" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name                                        = "${var.project_name}-public-${count.index + 1}"
      Type                                        = "public"
      "kubernetes.io/role/elb"                    = var.enable_eks ? "1" : null
      "kubernetes.io/cluster/${var.project_name}" = var.enable_eks ? "shared" : null
    }
  )
}

# =============================================================================
# Private Subnets
# =============================================================================

resource "aws_subnet" "private" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.vpc_availability_zones)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    local.common_tags,
    {
      Name                                        = "${var.project_name}-private-${count.index + 1}"
      Type                                        = "private"
      "kubernetes.io/role/internal-elb"           = var.enable_eks ? "1" : null
      "kubernetes.io/cluster/${var.project_name}" = var.enable_eks ? "shared" : null
    }
  )
}

# =============================================================================
# NAT Gateways (one per AZ for high availability)
# =============================================================================

resource "aws_eip" "nat" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nat-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# Route Tables - Public
# =============================================================================

resource "aws_route_table" "public" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-public-rt"
      Type = "public"
    }
  )
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# =============================================================================
# Route Tables - Private (one per AZ)
# =============================================================================

resource "aws_route_table" "private" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-private-rt-${count.index + 1}"
      Type = "private"
    }
  )
}

resource "aws_route_table_association" "private" {
  count = local.create_vpc ? var.vpc_availability_zones : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# Security Group - Default
# =============================================================================

resource "aws_security_group" "default" {
  count = local.create_vpc ? 1 : 0

  name_prefix = "${var.project_name}-default-"
  description = "Default security group for ${var.project_name}"
  vpc_id      = aws_vpc.main[0].id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Allow inbound from within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow all traffic within VPC"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-default-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
