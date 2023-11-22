variable "gcp_project_name" {
  type = string
  description = "name of gcp project where vm is to be created"
}
variable "credentials_filename" {
  type = string
  description = "path to gcp service account key json file"
}
variable "tsb_repo_username" {
  type = string
  description = "tsb repo username"
}
variable "tsb_repo_apikey" {
  type = string
  description = "tsb repo apikey"
}
