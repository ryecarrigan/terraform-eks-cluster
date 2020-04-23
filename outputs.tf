output "bastion_security_group_id" {
  value = aws_security_group.bastion.id
}

output "cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "control_plane_security_group_id" {
  value = aws_security_group.control_plane.id
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}
