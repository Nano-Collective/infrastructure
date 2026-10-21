terraform {
  # 1.10 is the floor because the S3 backend only gained native state locking
  # (use_lockfile) there. Before that a lock needed DynamoDB, which Cloudflare
  # R2 does not have.
  required_version = ">= 1.10.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }
}
