provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}
provider "google-beta" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}