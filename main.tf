data "aws_kms_key" "this" {
  count = var.kms_key_id == null ? 0 : 1

  key_id = var.kms_key_id
}

data "aws_subnet" "this" {
  for_each = toset(var.vpc_id == null ? [] : data.aws_subnets.this[0].ids)

  id = each.value
}

data "aws_subnets" "this" {
  count = var.vpc_id == null ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

locals {
  name_prefix = var.name
  tags        = module.name.tags
  kms_key_arn = try(data.aws_kms_key.this[0].arn, null)

  # only use the available zones we want to run in
  subnet_ids = try([
    for id in data.aws_subnet.this[0] : id.id
    if !contains(var.az_blacklist, id.availability_zone)
  ], null)
}

module "ec2_work" {
  count  = var.enable_ec2 ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-ec2?ref=v0.1.27"

  domain        = var.domain
  egress_cidr6s = var.egress_cidr6s
  egress_cidrs  = var.egress_cidrs
  key_name      = var.ec2_key_name
  name_prefix   = local.name_prefix
  ssh_cidr6s    = var.cidr6s
  ssh_cidrs     = var.cidrs
  subnet_id     = try(var.public_subnets[0], local.subnet_ids[0])
  tags          = local.tags
  vpc_id        = var.vpc_id
}

module "ecr" {
  for_each = toset(var.ecrs)
  source   = "github.com/s3d-club/terraform-aws-ecr?ref=v0.1.16"

  kms_key_arn = local.kms_key_arn
  name_prefix = each.key
  tags        = local.tags
}

module "name" {
  source = "github.com/s3d-club/terraform-external-name?ref=v0.1.15"

  context = var.name
  path    = path.module
  tags    = var.tags
}

# tfsec:ignore:aws-ec2-no-public-ingress-sgr
module "sg_ingress_open" {
  count  = var.cidrs == null ? 0 : 1
  source = "github.com/s3d-club/terraform-aws-sg_ingress_open?ref=v0.1.13"

  cidrs       = var.cidrs
  cidr6s      = var.cidr6s
  vpc_id      = var.vpc_id
  name_prefix = local.name_prefix
  tags        = local.tags
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

# We can't log the logging bucket
#   tfsec:ignore:aws-s3-enable-bucket-logging
#   tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket = "tf-log-${local.name_prefix}"
  tags   = local.tags
}

resource "aws_s3_bucket" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket = "tf-${local.name_prefix}"
  tags   = local.tags
}

resource "aws_s3_bucket_acl" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  acl    = "private"
  bucket = aws_s3_bucket.log[0].id
}

resource "aws_s3_bucket_acl" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  acl    = "private"
  bucket = aws_s3_bucket.this[0].id
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.enable_tf_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  target_bucket = aws_s3_bucket.log[0].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_public_access_block" "log" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.log[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.this[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.enable_tf_bucket ? 1 : 0
  bucket = aws_s3_bucket.log[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_tf_bucket ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}
