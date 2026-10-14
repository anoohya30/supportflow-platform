variable "region" {
  description = "AWS region for all lab resources"
  type        = string
  default     = "eu-west-2"
}

variable "owner" {
  description = "Tag value identifying who owns these lab resources"
  type        = string
  default     = "anoohya"
}

variable "github_repository" {
  description = "GitHub repo (owner/name) allowed to push images via OIDC"
  type        = string
  default     = "anoohya30/supportflow-platform"
}

variable "instance_type" {
  description = "EC2 size. m7i-flex.large = 2 vCPU / 8 GB, AWS Free plan eligible: fits k3s + two environments"
  type        = string
  default     = "m7i-flex.large"
}

variable "k3s_version" {
  description = "Pinned k3s release installed on the lab host"
  type        = string
  default     = "v1.36.5+k3s1"
}

variable "helm_version" {
  description = "Pinned Helm release installed on the lab host"
  type        = string
  default     = "v3.22.0"
}

variable "app_ingress_cidrs" {
  description = "Who may reach the app on port 80 (the only open port)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
