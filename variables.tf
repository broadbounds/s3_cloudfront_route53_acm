variable "aws_region" {
  type = string
  default = "us-east-2"
}

variable "access_key" {
  type        = string
  default     = ""
}

variable "secret_key" {
  type        = string
  default     = ""
}

variable "website-domain-main" {
  description = "Main website domain, e.g. cloudmaniac.net"
  type        = string
  default     = "resbbi.com"
}

variable "website-domain-redirect" {
  description = "Secondary FQDN that will redirect to the main URL, e.g. www.cloudmaniac.net"
  type        = string
  default     = "www.resbbi.com"
}


variable "tags" {
  description = "Tags added to resources"
  default     = {}
  type        = map(string)
}
