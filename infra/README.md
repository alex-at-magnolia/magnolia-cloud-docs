This is terraform configuration for internal cloud documentation site infrastructure. The infra is made of 
following resources:

- CloudFront distribution
- S3 bucket for hosting the site content
- R53 record for the main site domain
- ACM certificate to be associated with CloudFront distribution
- Authentication lambda

The site has a main domain which is managed in one of our Route53 hosted zone. The R53 zone and the 
certificate are assumed to be ready in advance. The certificate should include the main domain.

# Variables

- region: AWS region to deploy the infra (us-east-1 due to several resources being global and need to be based there)
- site_domain: main domain of the site, it's also used for S3 bucket name
- ssl_cert_domain: the 1st domain of the SSL cert in ACM, should match (or cover if it's a wildcard one) 
the site_domain. The ACM cert for this domain should be validated in the same specified region
- route53_hosted_zone: R53 hosted zone domain name