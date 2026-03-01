terraform {
  required_version = "~> 1.0"

  backend "gcs" {
    bucket = "manojsharma-terraform-state"
    prefix = "project-4/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}


# Configure the Google Cloud provider
provider "google" {
  project = "my-ever-first-project"   # Replace with your actual GCP project ID
  region  = "us-central1"           # Set region to us-central1
}

# Define zones to use
locals {
  zones = ["us-central1-a", "us-central1-b"]  # Two zones in the region
}

# Create a single VPC network
resource "google_compute_network" "main_vpc" {
  name                    = "main-vpc"        # Name of the VPC
  auto_create_subnetworks = false             # Disable automatic subnet creation
}

# Create a regional subnet that spans both zones
resource "google_compute_subnetwork" "main_subnet" {
  name          = "main-subnet"               # Name of the subnet
  ip_cidr_range = "10.0.0.0/16"               # CIDR block for subnet
  region        = "us-central1"               # Subnet region
  network       = google_compute_network.main_vpc.self_link  # Attach to VPC
}

# Create one VM in each zone
resource "google_compute_instance" "vm_nodes" {
  count        = length(local.zones)          # Create VM for each zone
  name         = "vm-node-${local.zones[count.index]}"  # VM name includes zone
  machine_type = "e2-micro"                   # Smallest free-tier eligible VM type
  zone         = local.zones[count.index]     # Place VM in respective zone

  # Define boot disk
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"        # OS image for VM
    }
  }

  # Attach VM to subnet
  network_interface {
    subnetwork   = google_compute_subnetwork.main_subnet.self_link
    access_config {}                          # Assign external IP
  }

  # Startup script to install PostgreSQL client
  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y postgresql-client
  EOT
}

# Create a single PostgreSQL Cloud SQL instance with HA
resource "google_sql_database_instance" "postgres_instance" {
  name              = "postgres-ha"           # Name of the DB instance
  region            = "us-central1"           # Region for DB
  database_version  = "POSTGRES_14"           # PostgreSQL version

  settings {
    tier = "db-f1-micro"                      # Smallest free-tier eligible DB tier
    availability_type = "REGIONAL"            # Enable HA across zones
    ip_configuration {
      private_network = google_compute_network.main_vpc.self_link  # Attach DB to VPC
    }
  }
}

# Create a default database inside the instance
resource "google_sql_database" "default_db" {
  name     = "appdb"                          # Database name
  instance = google_sql_database_instance.postgres_instance.name
}

# Create a user for the database
resource "google_sql_user" "db_user" {
  name     = "appuser"                        # Username
  instance = google_sql_database_instance.postgres_instance.name
  password = "StrongPassword123!"             # Password (replace with secure secret)
}