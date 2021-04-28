terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
    okta = {
      source  = "oktadeveloper/okta"
      version = "~> 3.6"
    }
  }
  required_version = ">= 0.13"
}
