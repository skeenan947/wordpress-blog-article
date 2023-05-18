terraform {
  backend "gcs" {
    bucket = "sk-wordpress-blog-tf"
    prefix = "blog"
  }
}
