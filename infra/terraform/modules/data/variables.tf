variable "name" {
  type = string
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "common_tags" {
  type = map(string)
}
