terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.69.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_filename)

  project = var.gcp_project_name
  region  = "us-central1"
  zone    = "us-central1-a"
}

resource "google_compute_instance" "tsb_vm" {
  name         = "tsb-vm"
  machine_type = "e2-standard-16"

  tags         = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size = 50
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    user-data = templatefile("${path.module}/vm-userdata.tftpl", {
      tsb_repo_username = var.tsb_repo_username
      tsb_repo_apikey = var.tsb_repo_apikey
    })
  }
}
