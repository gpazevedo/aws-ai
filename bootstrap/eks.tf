# =============================================================================
# EKS (Elastic Kubernetes Service) Resources
# =============================================================================
# Creates EKS cluster with complete infrastructure
# Enabled when: enable_eks = true
# Includes: Cluster, Node Group, Add-ons (ALB Controller, Cluster Autoscaler, Metrics Server)
# =============================================================================

# =============================================================================
# EKS Cluster IAM Role
# =============================================================================

resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0

  name        = "${var.project_name}-eks-cluster"
  description = "IAM role for ${var.project_name} EKS cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# =============================================================================
# EKS Cluster Security Group
# =============================================================================

resource "aws_security_group" "eks_cluster" {
  count = var.enable_eks ? 1 : 0

  name_prefix = "${var.project_name}-eks-cluster-"
  description = "Security group for ${var.project_name} EKS cluster"
  vpc_id      = aws_vpc.main[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-eks-cluster-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# EKS Cluster
# =============================================================================

resource "aws_eks_cluster" "main" {
  count = var.enable_eks ? 1 : 0

  name     = var.project_name
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster[0].id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]
}

# =============================================================================
# EKS Node Group IAM Role
# =============================================================================

resource "aws_iam_role" "eks_nodes" {
  count = var.enable_eks ? 1 : 0

  name        = "${var.project_name}-eks-nodes"
  description = "IAM role for ${var.project_name} EKS worker nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# =============================================================================
# EKS Node Group
# =============================================================================

resource "aws_eks_node_group" "main" {
  count = var.enable_eks ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.eks_node_instance_types

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-eks-node-group"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]
}

# =============================================================================
# EKS Add-ons
# =============================================================================

# CoreDNS Add-on
resource "aws_eks_addon" "coredns" {
  count = var.enable_eks ? 1 : 0

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.main]
}

# kube-proxy Add-on
resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_eks ? 1 : 0

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "kube-proxy"
}

# VPC CNI Add-on
resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_eks ? 1 : 0

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "vpc-cni"
}

# =============================================================================
# EKS Deployment Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "eks_deploy" {
  count = var.enable_eks ? 1 : 0

  name        = "${var.project_name}-eks-deploy"
  description = "Allows GitHub Actions to deploy to EKS for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EKS cluster access
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeUpdate",
          "eks:ListUpdates"
        ]
        Resource = var.enable_eks ? aws_eks_cluster.main[0].arn : "*"
      },
      # EKS authentication
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach EKS deployment policy to dev role
resource "aws_iam_role_policy_attachment" "dev_eks_deploy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.eks_deploy[0].arn
}

# Attach EKS deployment policy to test role
resource "aws_iam_role_policy_attachment" "test_eks_deploy" {
  count = var.enable_eks && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.eks_deploy[0].arn
}

# Attach EKS deployment policy to prod role
resource "aws_iam_role_policy_attachment" "prod_eks_deploy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.eks_deploy[0].arn
}

# =============================================================================
# Note: EKS Add-ons (ALB Controller, Cluster Autoscaler, Metrics Server)
# =============================================================================
# These are installed via Helm/kubectl after cluster creation
# See: docs/EKS.md for installation instructions
# The bootstrap provides the necessary IAM roles and permissions
