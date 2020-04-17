variable "bastion_count" {
  default = 1
}

variable "bastion_key_name" {
  default = ""
}

variable "cluster_name" {}
variable "eks_version" {
  default = "1.15"
}

variable "extra_tags" {
  default = {}
  type    = "map"
}

variable "private_subnet_ids" {
  type = "list"
}

variable "public_subnet_ids" {
  type = "list"
}

variable "ssh_cidr" {}
variable "vpc_id" {}

locals {
  cluster_name_tag = "kubernetes.io/cluster/${var.cluster_name}"
}
