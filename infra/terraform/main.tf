terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name = var.cluster_name
}

# 1. Customer-managed KMS key for encrypting EKS secrets
resource "aws_kms_key" "eks" {
  description             = "EKS cluster encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow administration of the key"
        Effect    = "Allow"
        Principal = { AWS = data.aws_caller_identity.current.arn }
        Action    = ["kms:*"]
        Resource  = "*"
      },
      {
        Sid       = "Allow EKS to use the key"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource  = "*"
      }
    ]
  })
}

# 2. IAM role for EKS control plane
resource "aws_iam_role" "eks_cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach required AWS-managed policies
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "service_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

# 3. Provision the encrypted EKS cluster
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster.arn

  # VPC configuration (supply your subnets)
  vpc_config {
    subnet_ids         = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Enable encryption of Kubernetes secrets
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }
}

# 4. IAM role for EKS worker nodes
resource "aws_iam_role" "eks_workers" {
  name = "${local.cluster_name}-workers-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach the standard Amazon EKS worker policies
resource "aws_iam_role_policy_attachment" "workers_node_policy" {
  role       = aws_iam_role.eks_workers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "workers_cni_policy" {
  role       = aws_iam_role.eks_workers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "workers_registry_policy" {
  role       = aws_iam_role.eks_workers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# 5. Managed EKS Node Group
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.eks_workers.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.micro"]

  ami_type = "BOTTLEROCKET_x86_64"

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.service_policy
  ]
}
