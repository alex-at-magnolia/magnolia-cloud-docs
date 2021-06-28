terraform {
  backend "s3" {
    bucket         = "magnolia-internal-docs-infra-tfstate"
    key            = "infra.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-states-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/sre-platform"
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/sre-platform"
  }
}

resource "aws_s3_bucket" "bucket" {
  bucket = var.site_domain
  acl    = "private"

  tags = {
    Organization = "Magnolia"
    Subscription = "Magnolia Internal Cloud Docs"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id
# aws_cloudfront_origin_access_identity.identity.iam_arn
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "2",
            "Effect": "Allow",
            "Principal": {
                "AWS": "AIDAI6577Z7YJ7JIN7P3W"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::docs.beta.de.magnolia-cloud.com/*"
        },
        {
            "Sid": "2",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_cloudfront_origin_access_identity.identity.iam_arn}"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::docs.beta.de.magnolia-cloud.com/*"
        }
    ]
}
POLICY

  depends_on = [aws_s3_bucket_public_access_block.public_access_block]
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.main_domain
  validation_method = "DNS"
  provider          = aws.us-east-1
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
  provider                = aws.us-east-1
}

data "aws_route53_zone" "r53_zone" {
  name = var.route53_hosted_zone
}

resource "aws_route53_record" "cert_validation" {
  name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.r53_zone.id
  records = [tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value]
  ttl     = "300"
}
resource "aws_route53_record" "r53_records" {
  name = var.site_domain
  type = "A"

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
  }
  zone_id = data.aws_route53_zone.r53_zone.zone_id
}


resource "aws_cloudfront_origin_access_identity" "identity" {
  comment = "docs.internal-okta"
}

locals {
  s3_origin_id = "InternalDocsAuth"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for S3-hosted website ${var.site_domain}"
  default_root_object = var.index_document

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn = aws_lambda_function.lambda_edge.qualified_arn
      include_body = true
    }

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${var.error_document}"
  }

  price_class = var.cloudfront_distribution_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Organization = "Magnolia"
    Subscription = "Magnolia Internal Cloud Docs"
  }

  aliases = concat([var.site_domain])

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }

  logging_config {
    bucket          = "internal-docs-logs.s3.amazonaws.com"
    include_cookies = false
    prefix          = "cloudfront/"
  }
}

# Lambda@edge
resource "aws_iam_role" "lambda_edge_exec" {
  name = "Internal-docs-lambda"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_edge_exec_policy" {
  name = "Internal-docs-lambda-policy"
  role = aws_iam_role.lambda_edge_exec.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds",
                "secretsmanager:ListSecrets"
            ],
            "Resource": [
                "arn:aws:secretsmanager:us-east-1:024110277478:secret:internal-docs-password-m2L2h0"
            ]
        }
    ]
}
EOF
}

resource "aws_lambda_function" "lambda_edge" { 
  publish  = true
  filename      = "lambda.zip"
  function_name = "auth_internal_docs"
  role          = aws_iam_role.lambda_edge_exec.arn
  handler       = "index.handler"
  runtime = "nodejs14.x"
}