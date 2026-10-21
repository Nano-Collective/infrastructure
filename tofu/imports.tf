# Importing what already exists: bring the repositories, teams and people that
# were created by hand into state without changing any of them. var.bootstrap
# below switches it off once that has been applied.
#
# import-ids.auto.tfvars.json beside this file is committed, and has to be. CI
# starts from empty state, so without it the ruleset and team imports have no
# ids and the plan fails with "Invalid index". It holds no secrets: a ruleset id
# and a team id are public facts about a public organisation.
#
# The catalogue under repos/ was generated from the live organisation, drift and
# all. The success criterion for the first apply is one line of output:
#
#   No changes. Your infrastructure matches the configuration.

variable "bootstrap" {
  description = <<-EOT
    Arms the import blocks in this file. True for the first apply and the first
    apply only.

    While it is on the catalogue can record what already exists but cannot add
    anything: a newly named repository, person or team grant has nothing to
    import and the plan fails with "Cannot import non-existent remote object".
    Turn it off in the pull request after the import has been applied.
  EOT
  type        = bool
  default     = true
}

variable "import_ruleset_ids" {
  description = "Generated. Keyed <repo>:<quality|review>, valued <repo>:<ruleset id>."
  type        = map(string)
  default     = {}
}

variable "import_team_ids" {
  description = "Generated. Team slug to numeric id."
  type        = map(string)
  default     = {}
}

import {
  for_each = { for k, v in local.repos : k => v if var.bootstrap }
  to       = module.repository[each.key].github_repository.this
  id       = each.key
}

import {
  for_each = { for k, v in local.repos : k => v if var.bootstrap }
  to       = module.repository[each.key].github_repository_vulnerability_alerts.this
  id       = each.key
}

import {
  for_each = { for k, v in var.import_ruleset_ids : k => v if var.bootstrap && endswith(k, ":quality") }
  to       = module.repository[split(":", each.key)[0]].github_repository_ruleset.quality[0]
  id       = each.value
}

import {
  for_each = { for k, v in var.import_ruleset_ids : k => v if var.bootstrap && endswith(k, ":review") }
  to       = module.repository[split(":", each.key)[0]].github_repository_ruleset.review[0]
  id       = each.value
}

import {
  for_each = { for k, v in var.import_team_ids : k => v if var.bootstrap && try(local.teams[k].parent, null) == null }
  to       = github_team.root[each.key]
  id       = each.value
}

import {
  for_each = { for k, v in var.import_team_ids : k => v if var.bootstrap && try(local.teams[k].parent, null) != null }
  to       = github_team.child[each.key]
  id       = each.value
}

import {
  for_each = { for k, v in var.import_team_ids : k => v if var.bootstrap }
  to       = github_team_members.this[each.key]
  id       = each.value
}

# github_team_repository wants <team id>:<repository name>.
import {
  for_each = { for k, v in local.team_grants : k => v if var.bootstrap }
  to       = github_team_repository.this[each.key]
  id       = "${var.import_team_ids[each.value.team]}:${each.value.repository}"
}

import {
  for_each = { for k, v in local.people : k => v if var.bootstrap }
  to       = github_membership.this[each.key]
  id       = "${var.organisation}:${each.key}"
}
