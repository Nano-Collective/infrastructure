# Authentication is a GitHub App, never a personal access token. An App belongs
# to the organisation, mints a token that lives an hour, and appears in the
# audit log under its own name.
#
# Two Apps, because the plan job and the apply job need different power:
#
#   nc-infra-plan   read only.  Used on pull requests.
#   nc-infra-apply  read write. Used after a merge, behind a human gate.
#
# The token is read from GITHUB_TOKEN and must never be passed as an OpenTofu
# variable. A saved plan records every variable value in plaintext whatever
# `sensitive` says, and apply.yml publishes its plan as a public artifact.
#
# Applying a saved plan also uses the variable values recorded in it and ignores
# TF_VAR_* from the environment. Provider credentials read from the environment
# are resolved at run time and never enter the plan.
#
# There is deliberately no app_auth block and no variable that could carry a
# credential, so the claim above holds structurally rather than by convention.
#
# Locally:  GITHUB_TOKEN=$(gh auth token) tofu plan
# In CI:    the workflow sets GITHUB_TOKEN from the App token it mints.

provider "github" {
  owner = var.organisation

  # The organisation is small and the API is rate limited per hour, not per
  # second. Slowing writes down costs a few seconds per apply and avoids the
  # secondary rate limit that a burst of ruleset writes can trip.
  write_delay_ms = 1000
  read_delay_ms  = 0
  max_retries    = 3
}
