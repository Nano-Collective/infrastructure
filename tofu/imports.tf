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
    apply only, which has happened: sixty-three objects on 2026-10-21, then this
    repository itself in the pull request after it.

    While it is on the catalogue can record what already exists but cannot add
    anything: a newly named repository, person or team grant has nothing to
    import and the plan fails with "Cannot import non-existent remote object".
    That is what it is now off for. It does not get turned back on to import
    something new -- a new repository is created by an apply, not imported, and
    arming this again would break every addition in the catalogue until it was
    turned off a second time. To adopt something that already exists by hand,
    arm it in its own pull request, apply, and disarm in the next one.
  EOT
  type        = bool
  default     = false
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

# --------------------------------------------- adopting nanocoder-desktop --
#
# Not gated on var.bootstrap, and deliberately not. That variable is for the one
# first apply and says so; arming it again to pick up a single team would break
# every addition made to the catalogue since. This is the narrow form its own
# documentation asks for instead -- "arm it in its own pull request, apply, and
# disarm in the next one" -- scoped to the one object that actually conflicts.
#
# Only the team needs it. github_team_repository, github_team_members and
# github_membership all write with PUT and reconcile an existing grant or
# membership without an import; github_team would 422.
#
# Delete this block in the pull request after the apply that uses it.
import {
  to = github_team.root["nanocoder-desktop"]
  id = "20259972"
}