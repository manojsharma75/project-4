terraform {
  required_version = "~> 1.0"

  # Store Terraform state remotely in a GCS bucket
  backend "gcs" {
    bucket = "manojsharma-terraform-state"   # GCS bucket name
    prefix = "project-4/state"               # Path/prefix inside the bucket
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"                     # Use Google provider v7.x
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = "my-ever-first-project"          # GCP project ID
  region  = "us-central1"                    # Default region
}

# Define zones to use for VM placement
locals {
  zones = ["us-central1-a", "us-central1-b"] # Two zones in the region
}

# Create a single VPC network (no auto subnets)
resource "google_compute_network" "main_vpc" {
  name                    = "main-vpc"
  auto_create_subnetworks = false
}

# Create a regional subnet inside the VPC
resource "google_compute_subnetwork" "main_subnet" {
  name          = "main-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.main_vpc.self_link
}

# Create one VM in each zone
resource "google_compute_instance" "vm_nodes" {
  count        = length(local.zones)
  name         = "vm-node-${local.zones[count.index]}"
  machine_type = "e2-micro"
  zone         = local.zones[count.index]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork   = google_compute_subnetwork.main_subnet.self_link
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y postgresql-client
  EOT
}

# --- Service Networking setup for Cloud SQL private IP ---

resource "google_project_service" "service_networking" {
  project = "my-ever-first-project"
  service = "servicenetworking.googleapis.com"
}

resource "google_compute_global_address" "private_ip_range" {
  name          = "google-managed-services-main-vpc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main_vpc.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main_vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [
    google_project_service.service_networking
  ]
}

# --- Cloud SQL Instance ---

resource "google_sql_database_instance" "postgres_instance" {
  name              = "postgres-ha"
  region            = "us-central1"
  database_version  = "POSTGRES_14"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main_vpc.self_link
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
}

resource "google_sql_database" "default_db" {
  name     = "appdb"
  instance = google_sql_database_instance.postgres_instance.name
}

resource "google_sql_user" "db_user" {
  name     = "appuser"
  instance = google_sql_database_instance.postgres_instance.name
  password = "StrongPassword123!"   # Replace with secure secret
}