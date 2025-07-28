variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "agentops-eks"
}

variable "k8s_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cluster VPC"
  type        = list(string)
}
