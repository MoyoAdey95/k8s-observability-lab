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
  description = "Node size. Chosen from the workload rather than from the price list. The observability stack requests roughly 2.5Gi across Prometheus, Grafana, Loki, Tempo and promtail, and an e2-small leaves about 1.4Gi allocatable once GKE's own system pods are accounted for. Two of those would not schedule the stack. e2-medium gives 4Gi each, which fits with room to spare."
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Node boot disk. Prometheus, Loki and Tempo all write to it in this lab, but only for a few hours of low traffic."
  type        = number
  default     = 50
}
