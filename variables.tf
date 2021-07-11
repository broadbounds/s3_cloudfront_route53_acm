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

variable "www-website-domain" {
  description = "Main website domain"
  type        = string
  default     = "www.resbbi.com"
}

variable "website-domain" {
  description = "Secondary website domain that will redirect to the main URL"
  type        = string
  default     = "resbbi.com"
}


variable "tags" {
  description = "Tags added to resources"
  default     = {}
  type        = map(string)
}
