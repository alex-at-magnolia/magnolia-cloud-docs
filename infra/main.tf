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
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
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

  block_public_acls       = false
  block_public_policy     = false
  restrict_public_buckets = false
  ignore_public_acls      = false
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
              "s3:GetObject",
              "s3:ListBucket"
            ],
            "Resource": [
              "arn:aws:s3:::${var.site_domain}/*",
              "arn:aws:s3:::${var.site_domain}"
            ]
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
# docs.beta.de.magnolia-cloud.com
# name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
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
  comment = "Origin access identity for docu web in S3 bucket ${var.site_domain}"
}

locals {
  s3_origin_id = "${var.site_domain}-s3-origin"
}

data "aws_cloudformation_export" "FunctionArn" {
//  depends_on = [aws_cloudformation_stack.okta-cloudfront-auth-docs-internal]
  provider = aws.us-east-1
  name = "okta-cloudfront-auth-docs-internal:CloudFrontAuthFunctionVersion"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
//  depends_on = [aws_cloudformation_stack.okta-cloudfront-auth-docs-internal]
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
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = data.aws_cloudformation_export.FunctionArn.value
      // "arn:aws:lambda:us-east-1:024110277478:function:okta-cloudfront-auth-docs-i-CloudFrontAuthFunction-u6m7KjC79amw:1"
      // aws_cloudformation_stack.okta-cloudfront-auth-docs-internal.outputs["CloudFrontAuthFunctionVersion"]
      include_body = false
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
}

#Okta Auth via CloudFormation Stack
resource "aws_cloudformation_stack" "okta-cloudfront-auth-docs-internal" {
  name          = "okta-cloudfront-auth-docs-internal"
  capabilities  = ["CAPABILITY_IAM"]
  template_body = <<STACK
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: SAM configuration for cloudfront-auth function
Resources:
  CloudFrontAuthFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: s3://internal-doc-sam/54a7ff20b2ae380aae9e31c8ed801f36
      Role:
        Fn::GetAtt:
        - LambdaEdgeFunctionRole
        - Arn
      Runtime: nodejs10.x
      Handler: index.handler
      Timeout: 5
      AutoPublishAlias: LIVE
  LambdaEdgeFunctionRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /
      ManagedPolicyArns:
      - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
        - Sid: AllowLambdaServiceToAssumeRole
          Effect: Allow
          Action:
          - sts:AssumeRole
          Principal:
            Service:
            - lambda.amazonaws.com
            - edgelambda.amazonaws.com
Outputs:
  CloudFrontAuthFunction:
    Description: Lambda@Edge CloudFront Auth Function ARN
    Value:
      Fn::GetAtt:
      - CloudFrontAuthFunction
      - Arn
  CloudFrontAuthFunctionVersion:
    Description: Lambda@Edge CloudFront Auth Function ARN with Version
    Value:
      Ref: CloudFrontAuthFunction.Version
    Export:
      Name: !Join [ ":", [ !Ref "AWS::StackName", CloudFrontAuthFunctionVersion ] ]
STACK
}

#Lambda@edge
# resource "aws_iam_role" "lambda_edge_exec" {
#   name = "Internal docs lambda permissions"
#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Action": "sts:AssumeRole",
#       "Principal": {
#         "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
#       },
#       "Effect": "Allow"
#     }
#   ]
# }
# EOF
# }

# resource "aws_lambda_function" "lambda_edge" {
#   provider = aws.us_east_1
#   publish  = true
#   filename      = "lambda.zip"
#   function_name = "auth_internal_docs"
#   role          = aws_iam_role.lambda_edge_exec.arn
#   handler       = "index.handler"
#   runtime = "nodejs14.x"
# }
