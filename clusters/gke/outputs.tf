output "cluster_name" {
  value = google_container_cluster.obs_lab.name
}

output "get_credentials" {
  description = "Command to point kubectl at the new cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.obs_lab.name} --zone ${var.zone} --project ${var.project_id}"
}

output "node_pool_machine_type" {
  description = "Handy when checking what is actually running against what was intended."
  value       = google_container_node_pool.spot.node_config[0].machine_type
}
