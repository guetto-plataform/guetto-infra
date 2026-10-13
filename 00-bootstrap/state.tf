# Bucket que guarda o state de todas as camadas desta conta (inclusive o desta, após a migração).

locals {
  # Namespace regional da conta: só esta conta pode criar um bucket com este sufixo.
  state_bucket_name = "guetto-tfstate-${var.account_id}-${var.region}-an"
}

resource "aws_s3_bucket" "state" {
  bucket           = local.state_bucket_name
  bucket_namespace = "account-regional"

  # Apagar este bucket apaga o histórico de todas as camadas. Para destruir de propósito,
  # remova esta trava num commit explícito.
  lifecycle {
    prevent_destroy = true
  }
}

# Cada escrita do state vira uma versão: permite voltar a um state anterior se ele corromper.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 já é o padrão desde 2023; declarado para o requisito ficar explícito no código.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Desliga ACLs: o acesso é controlado só por políticas IAM/bucket policy.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  # Serializa as alterações no bucket: chamadas simultâneas podem falhar com OperationAborted.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# Versionamento sem expiração acumula versões antigas (e os .tflock apagados a cada lock).
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expirar-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "limpar-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}
