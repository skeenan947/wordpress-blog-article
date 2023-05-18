# Create a Cloud SQL instance
resource "google_sql_database_instance" "wordpress_cloud_sql_instance" {
  name             = "wordpress-cloud-sql-instance"
  database_version = "MYSQL_5_7"

  settings {
    tier              = "db-f1-micro"
    activation_policy = "ALWAYS"
    disk_autoresize   = true
    disk_size         = 10
  }
}

# Create a Cloud SQL database
resource "google_sql_database" "wordpress_cloud_sql_database" {
  name     = "wordpress-database"
  instance = google_sql_database_instance.wordpress_cloud_sql_instance.name
}

resource "google_sql_user" "wordpress" {
  name     = "wordpress"
  instance = google_sql_database_instance.wordpress_cloud_sql_instance.name
  password = "changeme"
}

# Create a serverless VPC connector
resource "google_compute_network" "wordpress_vpc_network" {
  name                    = "wordpress-vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "wordpress_vpc_subnetwork" {
  name          = "wordpress-vpc-subnetwork"
  network       = google_compute_network.wordpress_vpc_network.name
  ip_cidr_range = "10.0.0.0/16"
}
resource "google_compute_subnetwork" "wordpress_vpc_connector" {
  name          = "wordpress-vpc-connector"
  network       = google_compute_network.wordpress_vpc_network.name
  ip_cidr_range = "10.1.0.0/28"
}

resource "google_vpc_access_connector" "wordpress_connector" {
  name = "vpc-con"
  subnet {
    name = google_compute_subnetwork.wordpress_vpc_connector.name
  }
  machine_type = "f1-micro"
}

# Create a Cloud Run service
resource "google_cloud_run_service" "wordpress_cloud_run_service" {
  name     = "wordpress-cloud-run-service"
  location = "us-central1"
  template {
    spec {
      containers {
        image = "${google_artifact_registry_repository.wordpress_artifact_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wordpress_artifact_registry.name}/wordpress:latest"
        ports {
          container_port = "80"
        }
        env {
          name  = "DB_HOST"
          value = "localhost:/cloudsql/${google_sql_database_instance.wordpress_cloud_sql_instance.connection_name}"
        }
        env {
          name  = "DB_NAME"
          value = "wordpress-database"
        }
        env {
          name  = "DB_USER"
          value = "wordpress"
        }
        env {
          name  = "DB_PASS"
          value = "changeme"
        }
        env {
          name  = "WP_NFS_SERVER"
          value = google_filestore_instance.wordpress_filestore.networks[0].ip_addresses[0]
        }
        env {
          name  = "WP_NFS_SHARE"
          value = "/${google_filestore_instance.wordpress_filestore.file_shares[0].name}"
        }
        env {
          name  = "WP_NFS_VERSION"
          value = "3"
        }
        env {
          name  = "WP_BASEURL"
          value = "https://wordpress-cloud-run-service-mcxbilzxna-uc.a.run.app/"
        }
        env {
          name  = "WP_DEBUG"
          value = "true"
        }
      }
    }

    metadata {
      annotations = {
        # Limit scale up to prevent any cost blow outs!
        "autoscaling.knative.dev/maxScale" = "5"
        # Use the VPC Connector
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.wordpress_connector.name
        # all egress from the service should go through the VPC Connector
        "run.googleapis.com/vpc-access-egress" = "private-ranges-only"
        # add Cloud SQL proxy
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.wordpress_cloud_sql_instance.connection_name
        # Set execution env for NFS support
        "run.googleapis.com/execution-environment" = "gen2"
      }
    }
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.wordpress_cloud_run_service.location
  project  = google_cloud_run_service.wordpress_cloud_run_service.project
  service  = google_cloud_run_service.wordpress_cloud_run_service.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# Create a Google Cloud Artifact Registry instance
resource "google_artifact_registry_repository" "wordpress_artifact_registry" {
  location      = "us-central1"
  repository_id = "wordpress-artifacts"
  format        = "DOCKER"
}

# Create a Google Cloud Filestore instance
resource "google_filestore_instance" "wordpress_filestore" {
  name = "wordpress"
  tier = "STANDARD"
  file_shares {
    name        = "wordpress"
    capacity_gb = 1024
    nfs_export_options {
      ip_ranges   = ["10.1.0.0/28"]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }
  networks {
    network           = google_compute_network.wordpress_vpc_network.name
    reserved_ip_range = "10.2.0.0/29"
    connect_mode      = "DIRECT_PEERING"
    modes             = ["MODE_IPV4"]
  }
}