variable "project_id" {
  description = "GCP project to create the cluster in."
  type        = string
}

variable "region" {
  description = "Region for regional resources."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone for the cluster. Zonal on purpose, a zonal cluster's management fee sits inside the GKE free-tier credit while a regional cluster's does not."
  type        = string
  default     = "europe-west1-b"
}

variable "cluster_name" {
  type    = string
  default = "obs-lab"
}

variable "node_count" {
  description = "Nodes in the spot pool."
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Node size. Chosen from the workload rather than from the price list. The observability stack requests roughly 2.5Gi across Prometheus, Grafana, Loki, Tempo and promtail, and an e2-small leaves about 1.4Gi allocatable once GKE's own system pods are accounted for, so e2-medium was the original choice. Running it showed CPU was the binding constraint instead, with both nodes near 90% of allocatable CPU requests and nothing left for the HPA. Argo CD then adds a controller, repo-server, Redis and an API server on top of that. e2-standard-2 gives 2 vCPU and 8Gi per node, which leaves the scheduler somewhere to put them."
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Node boot disk. Prometheus, Loki and Tempo all write to it in this lab, but only for a few hours of low traffic."
  type        = number
  default     = 50
}
