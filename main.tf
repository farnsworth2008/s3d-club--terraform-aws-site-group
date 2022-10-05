data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "k8_master" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.account_id]
    }
  }
}

data "aws_kms_key" "this" {
  count = var.kms_key_id == null ? 0 : 1

  key_id = var.kms_key_id
}

data "aws_subnet" "this" {
  for_each = toset(data.aws_subnets.this.ids)

  id = each.value
}

data "aws_subnets" "this" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

locals {
  account_id  = data.aws_caller_identity.this.account_id
  name_prefix = module.name.prefix
  tags        = module.name.tags
  kms_key_arn = try(data.aws_kms_key.this[0].arn, null)

  # If the user supplies an EC2 Keyname we use theirs and do not create one for
  # the Site Group.
  ec2_key_name = (
    coalesce(var.ec2_key_name, "${local.name_prefix}-0")
  )

  # only use the available zones we want to run in
  subnet_ids = try([
    for id in data.aws_subnet.this : id.id
    if !contains(var.az_blacklist, id.availability_zone)
  ], null)
}

module "ec2_work" {
  count  = var.enable_ec2 ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-ec2?ref=v0.1.7"

  cidr6s    = var.cidr6s
  cidrs     = var.cidrs
  domain    = var.domain
  key_name  = local.ec2_key_name
  project   = "admin"
  subnet_id = try(var.public_subnets[0], local.subnet_ids[0])
  suffix    = join("-", [local.name_prefix, count.index])
  tags      = local.tags
  template  = "work"
  vpc_id    = var.vpc_id
}

module "ecr" {
  for_each = toset(var.ecrs)
  source   = "github.com/s3d-club/terraform-aws-ecr?ref=v0.1.4"

  kms_key_arn = local.kms_key_arn
  name_prefix = each.key
}

module "eks" {
  count  = var.enable_eks ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-eks?ref=v0.1.3"

  cidrs             = var.cidrs
  kms_key_arn       = local.kms_key_arn
  cluster_version   = var.eks_version
  name_prefix       = local.name_prefix
  tags              = local.tags
  subnet_ids        = local.subnet_ids
  security_group_id = module.sg_ingress_open[0].security_group_id
}

module "k8_auth" {
  count      = var.enable_k8_auth ? 1 : 0
  depends_on = [module.eks]
  source     = "github.com/s3d-club/terraform-kubernetes-aws-auth?ref=v0.0.5"

  cluster_name    = module.eks[0].cluster.name
  region          = var.region
  master_role_arn = aws_iam_role.k8_master.arn
}

module "name" {
  source = "github.com/s3d-club/terraform-external-name?ref=v0.1.3"

  context = var.name_prefix
  path    = path.module
  tags    = var.tags
}

# tfsec:ignore:aws-ec2-no-public-ingress-sgr
module "sg_ingress_open" {
  count  = var.cidrs == null ? 0 : 1
  source = "github.com/s3d-club/terraform-aws-sg_ingress_open?ref=v0.1.3"

  cidr        = var.cidrs
  cidr6       = var.cidr6s
  vpc         = var.vpc_id
  name_prefix = local.name_prefix
  tags        = local.tags
}

resource "aws_iam_role" "k8_master" {
  name               = local.name_prefix
  tags               = local.tags
  assume_role_policy = data.aws_iam_policy_document.k8_master.json
}

# We can't log the logging bucket
#   tfsec:ignore:aws-s3-enable-bucket-logging
#   tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket_prefix = "${local.name_prefix}-tf-log-"
  tags          = local.tags

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = var.kms_key_id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket_prefix = "${local.name_prefix}-tf-"
  tags          = local.tags

  logging {
    target_bucket = aws_s3_bucket.log[0].id
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = var.kms_key_id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_acl" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  acl    = "private"
  bucket = aws_s3_bucket.log[0].id
}

resource "aws_s3_bucket_public_access_block" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.log[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  acl    = "private"
  bucket = aws_s3_bucket.this[0].id
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.this[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# We do not need recovery for the locks
#   tfsec:ignore:aws-dynamodb-enable-recovery
resource "aws_dynamodb_table" "this" {
  count = var.enable_tf_lock_table ? 1 : 0

  hash_key       = "LockID"
  name           = "${local.name_prefix}-tf-lock"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }
}