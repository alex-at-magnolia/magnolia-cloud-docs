variable "region" {}

variable "account_id" {}

variable "site_domain" {
  description = "FQDN of the site and also the bucket name"
}

variable "main_domain" {
  description = "To create a certificate on us-east-1"
}

variable "index_document" {
  default = "index.html"
}

variable "error_document" {
  default = "404.html"
}

variable "ssl_cert_domain" {
  description = "SSL Certification Domain Name"
}

variable "cloudfront_distribution_price_class" {
  default = "PriceClass_100"
}

variable "route53_hosted_zone" {
  description = "Name of Route53 hosted zone"
}