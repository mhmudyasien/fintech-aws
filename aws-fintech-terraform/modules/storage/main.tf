variable "project_name" {}
variable "environment" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-data-lake-${var.environment}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Free managed keys
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_object" "mains_folders" {
  for_each = toset(["raw/", "processed/", "archive/"])
  bucket   = aws_s3_bucket.data_lake.id
  key      = each.value
}

output "bucket_name" {
  value = aws_s3_bucket.data_lake.id
}
