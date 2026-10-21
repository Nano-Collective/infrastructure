variable "organisation" {
  description = "GitHub organisation login. Capitalised exactly as GitHub stores it."
  type        = string
  default     = "Nano-Collective"
}

# There is deliberately no github_token variable: a saved plan records every
# variable value in plaintext regardless of `sensitive`. The token reaches the
# provider through GITHUB_TOKEN in the environment. See providers.tf.

variable "manage_org_settings" {
  description = <<-EOT
    Off by default. github_organization_settings is all or nothing: it sets
    every field on the organisation, including ones nobody has recorded, and it
    requires billing_email, which needs admin:org to read.

    Until those values are recorded, org/settings.yaml is documentation and
    scripts/readback.mjs fails if the live organisation has moved. Flip this to
    true in the pull request that adds the missing fields.
  EOT
  type        = bool
  default     = false
}

variable "billing_email" {
  description = "Required by github_organization_settings. Only read when manage_org_settings is true."
  type        = string
  sensitive   = true
  default     = ""
}
