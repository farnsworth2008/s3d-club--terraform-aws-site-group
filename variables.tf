variable "az_blacklist" {
  default = []
  type    = list(string)

  description = <<-EOT
    A list of avalibility zones that should not be used.
    EOT
}

variable "cidr6s" {
  default = []
  type    = list(string)

  description = <<-EOT
    A list of CIDRs.
    EOT
}

variable "cidrs" {
  default = null
  type    = list(string)

  description = <<-EOT
    A list of CIDRs.
    EOT
}

variable "domain" {
  default = null
  type    = string

  description = <<-EOT
    A domain that already has a route 53 hosted zone.
    EOT
}

variable "ec2_key_name" {
  default = null
  type    = string

  description = <<-EOT
    An ec2 key name.
    EOT
}

variable "ecrs" {
  default = []
  type    = list(string)

  description = <<-EOT
    A list of names for the ECR instances.
    EOT
}

variable "egress_cidr6s" {
  default = []
  type    = list(string)

  description = <<-EOT
    A list of addresses for open egress.
    EOT
}

variable "egress_cidrs" {
  default = null
  type    = list(string)

  description = <<-EOT
    A list of addresses for open egress.
    EOT
}

variable "enable_admin_iam_user" {
  default = false
  type    = bool

  description = <<-EOT
    An option to enable an IAM user intended for adminstration of the site
    group.
    EOT
}

variable "enable_ec2" {
  default = false
  type    = bool

  description = <<-EOT
    An option to enable the EC2 instance.
    EOT
}

variable "enable_tf_bucket" {
  default = false
  type    = bool

  description = <<-EOT
    An option that enables the creation of an S3 Bucket for storage of Terraform state.
    EOT
}

variable "enable_tf_lock_table" {
  default = false
  type    = bool

  description = <<-EOT
    An option that enables the creation of a DynamoDB table for Terraform locks.
    EOT
}

variable "kms_key_id" {
  type = string

  description = <<-EOT
    The ID of a KMS key.
    EOT
}

variable "name" {
  type = string

  description = <<-EOT
    A logical name for the site group and prefix for the associated resource names.
    EOT
}

variable "public_subnets" {
  default = null
  type    = list(string)

  description = <<-EOT
    A list of subnets where instances that should be public may be placed. Or
    the value `null` if a random subnet should be used.
    EOT
}

variable "tags" {
  default = {}
  type    = map(string)

  description = <<-EOT
    A map of tags for resources.
    EOT
}

variable "vpc_id" {
  default = null
  type    = string

  description = <<-EOT
    A VPC ID.
    EOT
}
