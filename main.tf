# Reference existing network resources via data sources.

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Determine which AZs support the selected server instance type (e.g., t4g.small may not be in all AZs).
data "aws_ec2_instance_type_offerings" "k3s_server_type" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.k3s_server_instance_type]
  }
  # Region is inherited from provider (var.aws_region)
}

locals {
  supported_azs = data.aws_ec2_instance_type_offerings.k3s_server_type.locations
  # Keep only subnets whose AZ supports the instance type
  filtered_subnet_ids       = [for s in data.aws_subnet.public : s.id if contains(local.supported_azs, s.availability_zone)]
  effective_subnet_ids      = length(local.filtered_subnet_ids) > 0 ? local.filtered_subnet_ids : [for s in data.aws_subnet.public : s.id]
  k3s_oidc_issuer_host_path = trimprefix(var.k3s_service_account_issuer, "https://")
  k3s_eso_auth_role_arn     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.k3s_eso_auth_role_name}"
  k3s_eso_ssm_role_arn      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.k3s_eso_ssm_role_name}"
  k3s_eso_ssm_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${var.k3s_eso_ssm_parameter_path}*"
}

data "aws_iam_policy_document" "k3s_oidc_test_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.k3s.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.k3s_oidc_issuer_host_path}:aud"
      values = [
        "sts.amazonaws.com",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.k3s_oidc_issuer_host_path}:sub"
      values = [
        "system:serviceaccount:${var.k3s_oidc_test_service_account_namespace}:${var.k3s_oidc_test_service_account_name}",
      ]
    }
  }
}

resource "aws_iam_openid_connect_provider" "k3s" {
  url = var.k3s_service_account_issuer

  client_id_list = [
    "sts.amazonaws.com",
  ]

  tags = merge(var.tags, {
    Name = "k3s-oidc-provider"
  })
}

resource "aws_iam_role" "k3s_oidc_test" {
  name               = var.k3s_oidc_test_role_name
  assume_role_policy = data.aws_iam_policy_document.k3s_oidc_test_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "k3s_eso_auth_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.k3s.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.k3s_oidc_issuer_host_path}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.k3s_oidc_issuer_host_path}:sub"
      values   = ["system:serviceaccount:external-secrets:eso-aws-auth"]
    }
  }
}

data "aws_iam_policy_document" "k3s_eso_auth_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.k3s_eso_ssm_role_arn]
  }
}

data "aws_iam_policy_document" "k3s_eso_ssm_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.k3s_eso_auth_role_arn]
    }
  }
}

data "aws_iam_policy_document" "k3s_eso_ssm_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [local.k3s_eso_ssm_parameter_arn]
  }
}

resource "aws_iam_role" "k3s_eso_auth" {
  name               = var.k3s_eso_auth_role_name
  assume_role_policy = data.aws_iam_policy_document.k3s_eso_auth_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "k3s_eso_auth_assume_ssm" {
  name   = "assume-ssm-parameter-read"
  role   = aws_iam_role.k3s_eso_auth.id
  policy = data.aws_iam_policy_document.k3s_eso_auth_permissions.json
}

resource "aws_iam_role" "k3s_eso_ssm" {
  name               = var.k3s_eso_ssm_role_name
  assume_role_policy = data.aws_iam_policy_document.k3s_eso_ssm_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "k3s_eso_ssm_read" {
  name   = "read-approved-ssm-parameters"
  role   = aws_iam_role.k3s_eso_ssm.id
  policy = data.aws_iam_policy_document.k3s_eso_ssm_permissions.json
}

# Reference existing EIP for nginx (managed outside Terraform, never destroyed)
data "aws_eip" "nginx" {
  id = var.nginx_eip_allocation_id
}

# The k3s cluster module
module "k3s" {
  source                     = "./modules/k3s-cluster"
  vpc_id                     = data.aws_vpc.existing.id
  subnet_ids                 = local.effective_subnet_ids
  server_instance_type       = var.k3s_server_instance_type
  agent_instance_type        = var.k3s_agent_instance_type
  server_eip_allocation_id   = var.k3s_server_eip_allocation_id
  ssm_token_name             = var.ssm_token_name
  ssm_kubeconfig_name        = var.ssm_kubeconfig_name
  ssm_argocd_password_name   = var.ssm_argocd_password_name
  service_account_issuer     = var.k3s_service_account_issuer
  nginx_security_group_id    = module.nginx_ingress.security_group_id
  create_nginx_nodeport_rule = true
  tags                       = var.tags
  key_name                   = var.key_name
  ssh_allowed_cidrs          = var.ssh_allowed_cidrs
  kubectl_allowed_cidrs      = var.kubectl_allowed_cidrs
}

# The nginx ingress module
module "nginx_ingress" {
  source = "./modules/nginx-ingress"

  vpc_id                         = data.aws_vpc.existing.id
  subnet_id                      = local.effective_subnet_ids[0]
  instance_type                  = var.nginx_instance_type
  eip_allocation_id              = data.aws_eip.nginx.id
  k3s_server_private_ip          = module.k3s.server_private_ip
  key_name                       = var.key_name
  ssh_allowed_cidrs              = var.ssh_allowed_cidrs
  tags                           = var.tags
  tls_certificate_parameter_name = var.nginx_tls_certificate_parameter_name
  tls_ca_bundle_parameter_name   = var.nginx_tls_ca_bundle_parameter_name
  tls_private_key_parameter_name = var.nginx_tls_private_key_parameter_name
  tls_kms_key_arn                = var.nginx_tls_kms_key_arn
}
