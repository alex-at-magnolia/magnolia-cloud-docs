provider "okta" {
  org_name  = "magnolia-cloud"
  base_url  = "okta.com"
}

locals {
  auth_server_name  = "magnolia-cloud-sso"
  user_email_prefix = "sre"
  user_email_suffix = "magnolia-cms.com"
}

data "okta_auth_server" "sso_auth_server" {
  name = local.auth_server_name
}

# resource "okta_app_oauth" "sso_app" {
#   for_each = var.deployments

#   label          = each.value
#   type           = "web"
#   grant_types    = ["authorization_code"]
#   redirect_uris  = ["https://author-${each.value}.${var.base_domain}/.auth?client_name=OidcClient"]
#   response_types = ["code"]
#   issuer_mode    = "ORG_URL"

#   lifecycle {
#     ignore_changes = [groups]
#   }
# }

resource "okta_app_oauth" "sso_app" {
  label                      = "Authorisation for Internal documentation"
  type                       = "web"
  grant_types                = ["authorization_code"]
  # redirect_uris              = ["https://${aws_cloudfront_distribution.s3_distribution.domain_name}"] site_domain
  redirect_uris              = ["https://${var.site_domain}"]
  response_types             = ["code"]
  issuer_mode                = "ORG_URL"
  lifecycle {
    ignore_changes = [groups]
  }
}
resource "okta_group" "deployment_groups" {
  name        = "Internal Cloud Docs group"
  description = "Internal Cloud Docs subscription group"
}

resource "okta_app_group_assignment" "deployment_group_to_sso_app_assignments" {
  app_id   = okta_app_oauth.sso_app.id
  group_id = okta_group.deployment_groups.id
}

#resource "okta_user" "deployment_users" {
#  for_each = var.deployments
#
#  email             = "${local.user_email_prefix}+${each.value}@${local.user_email_suffix}"
#  login             = "${local.user_email_prefix}+${each.value}@${local.user_email_suffix}"
#  first_name        = each.value
#  last_name         = "subscription"
#  group_memberships = [okta_group.deployment_groups[each.key].id]
#}

# Retrieve the 'mgnl-cloud-staff' group
data "okta_group" "mgnl_cloud_staff_group" {
  name = "mgnl-cloud-staff"
}

# Assign the 'mgnl-cloud-staff' group to the SSO application
resource "okta_app_group_assignment" "mgnl_cloud_staff_group_to_sso_app_assignment" {
  app_id   = okta_app_oauth.sso_app.id
  group_id = data.okta_group.mgnl_cloud_staff_group.id
}