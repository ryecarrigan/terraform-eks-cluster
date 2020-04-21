resource "aws_eks_cluster" "cluster" {
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  name                      = var.cluster_name
  role_arn                  = aws_iam_role.eks_service_role.arn
  version                   = var.eks_version

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.control_plane.id]
    subnet_ids              = var.private_subnet_ids
  }
}

resource "aws_instance" "bastion" {
  count = var.bastion_count

  ami                    = data.aws_ami.nat.id
  instance_type          = "t3.nano"
  key_name               = var.bastion_key_name
  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = merge(
    {
      Name = "${var.cluster_name}-bastion",
    },
    var.extra_tags,
  )
}

resource "aws_iam_role" "eks_service_role" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_eks.json
  name               = "eksServiceRole-${var.cluster_name}"

  tags = var.extra_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_service_role.id
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_service_role.id
}

data "aws_iam_policy_document" "assume_role_eks" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      identifiers = ["eks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_security_group" "control_plane" {
  description = "Security group for the EKS control plane"
  name        = "${var.cluster_name}-ControlPlane"
  vpc_id      = var.vpc_id

  tags = var.extra_tags
}

resource "aws_security_group" "node" {
  description = "Security group for all nodes in the cluster"
  name        = "${var.cluster_name}-Node"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      "${local.cluster_name_tag}" = "owned"
    },
    var.extra_tags,
  )
}

resource "aws_security_group" "bastion" {
  description = "Security group for the bastion server"
  name        = "${var.cluster_name}-Bastion"
  vpc_id      = var.vpc_id

  tags = var.extra_tags
}

/*
 * Because rules link the security groups, they must be managed seperately to avoid cyclic dependency.
 */

# Control plane SG rules
resource "aws_security_group_rule" "control_plane_node" {
  description              = "Allow the cluster control plane to communicate with worker Kubelet and pods"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control_plane.id
  source_security_group_id = aws_security_group.node.id
  to_port                  = 65535
  type                     = "egress"
}

resource "aws_security_group_rule" "control_plane_node_443_egress" {
  description              = "Allow the cluster control plane to communicate with pods running extension API servers on port 443"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control_plane.id
  source_security_group_id = aws_security_group.node.id
  to_port                  = 443
  type                     = "egress"
}

resource "aws_security_group_rule" "control_plane_node_443_ingress" {
  description              = "Allow pods to communicate with the cluster API Server on port 443"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control_plane.id
  source_security_group_id = aws_security_group.node.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "control_plane_bastion" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control_plane.id
  source_security_group_id = aws_security_group.bastion.id
  to_port                  = 443
  type                     = "ingress"
}

# Node SG rules
resource "aws_security_group_rule" "node_bastion" {
  description              = "Allows SSH traffic to the nodes from the bastion"
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.bastion.id
  to_port                  = 22
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_self" {
  description       = "Allow nodes to communicate with each other"
  from_port         = 0
  protocol          = "all"
  security_group_id = aws_security_group.node.id
  self              = true
  to_port           = 65535
  type              = "ingress"
}

resource "aws_security_group_rule" "node_control_plane" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.control_plane.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_control_plane_443" {
  description              = "Allow pods running extension API servers on port 443 to receive communication from cluster control plane"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.control_plane.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_egress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "all"
  security_group_id = aws_security_group.node.id
  to_port           = 0
  type              = "egress"
}

# Bastion SG rules
resource "aws_security_group_rule" "bastion_egress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion.id
  to_port           = 65535
  type              = "egress"
}

resource "aws_security_group_rule" "bastion_ingress" {
  cidr_blocks       = [var.ssh_cidr]
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion.id
  to_port           = 22
  type              = "ingress"
}

data "aws_ami" "nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat*"]
  }
}
