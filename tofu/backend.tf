terraform {
  # Cloudflare R2, reached through the S3 backend.
  #
  # R2 has no DynamoDB, so the lock is use_lockfile, which writes a .tflock
  # object next to the state using a conditional PUT. R2 supports those.
  #
  # The endpoint is not set here and is not passed with -backend-config. Both
  # would record the account id in every saved plan, which apply.yml publishes
  # as a build artifact on a public repository. It comes from
  # AWS_ENDPOINT_URL_S3 instead, which the AWS SDK resolves at run time and the
  # plan never serialises -- the same reason the token comes from the
  # environment. Every step that touches state has to set it.
  backend "s3" {
    bucket = "nc-tofu-state"
    key    = "github/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    # Path style, because R2 cannot do the other one.
    #
    # The S3 backend defaults to virtual-hosted addressing, which puts the
    # bucket in the hostname: nc-tofu-state.<account>.r2.cloudflarestorage.com.
    # R2 serves a single-level wildcard certificate for
    # *.r2.cloudflarestorage.com, and a wildcard matches one label, so that name
    # is not covered and init dies on a TLS handshake failure rather than on
    # anything that mentions buckets or credentials. Path style asks for
    # <account>.r2.cloudflarestorage.com/nc-tofu-state instead, which is the
    # form Cloudflare documents.
    use_path_style = true

    # R2 is S3-compatible, not S3. These four turn off the checks that only
    # make sense against the real thing.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
