terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "moyo-cloud-lab-tfstate"
    prefix = "k8s-observability-lab"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
