variable "aws_region" {
  description = "AWS region in which to deploy resources."
  type        = string
  default     = "us-east-2"
}

variable "prometheus_version" {
  description = "Prometheus version to install"
  type        = string
  default     = "2.45.0"
}

variable "node_exporter_version" {
  description = "Prometheus Node Exporter version to install"
  type        = string
  default     = "1.6.1"
}

