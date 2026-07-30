variable "project" {
  description = "Project name used for naming/tagging."
  type        = string
  default     = "pulseops"
}

variable "environment" {
  description = "Environment name (staging|production)."
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread across."
  type        = number
  default     = 2
}

# --- Application image tags (immutable: git SHA or semver, never 'latest') ---
variable "api_image" {
  description = "Fully qualified API/worker image, e.g. <ecr>/pulseops-app:<sha>."
  type        = string
}

variable "web_image" {
  description = "Fully qualified web image, e.g. <ecr>/pulseops-web:<sha>."
  type        = string
}

# --- Sizing (kept small by default; override per-env) ---
variable "api_desired_count" {
  type    = number
  default = 2
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

variable "api_cpu" {
  type    = number
  default = 256
}

variable "api_memory" {
  type    = number
  default = 512
}

variable "worker_cpu" {
  type    = number
  default = 256
}

variable "worker_memory" {
  type    = number
  default = 512
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}
