variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "user_email" {
  description = "User email for permissions"
  type        = string
  default     = "gsmacrehelp@gmail.com" # replace with your gcp email
}
