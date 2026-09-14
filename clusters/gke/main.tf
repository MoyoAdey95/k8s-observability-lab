# Zonal GKE cluster for the evidence phase of this lab. It exists for
# an afternoon. Iteration happens on kind, this cluster only proves the
# same manifests and Helm values work on a managed control plane.

resource "google_container_cluster" "obs_lab" {
  name     = var.cluster_name
  location = var.zone

  # the default node pool cannot be configured as spot, so it is
  # created at minimum size and removed, and a dedicated pool defined
  # below takes its place
  remove_default_node_pool = true
  initial_node_count       = 1

  # this cluster is disposable by design, and both earlier labs in this
  # series lost time to a destroy that stopped on this flag
  deletion_protection = false

  # keep GKE's own logging and monitoring to system components only.
  # The workload telemetry pipeline is the point of this repo, and
  # shipping the same logs to Cloud Logging as well would mean paying
  # to ingest them twice.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  release_channel {
    channel = "REGULAR"
  }
}

resource "google_container_node_pool" "spot" {
  name     = "spot-pool"
  cluster  = google_container_cluster.obs_lab.name
  location = var.zone

  node_count = var.node_count

  node_config {
    # spot nodes can be reclaimed with 30 seconds notice, which is
    # acceptable here and roughly 60 to 90% cheaper. The deployment's
    # topology spread constraint in the gke overlay is the workload
    # side of that bargain.
    spot         = true
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
