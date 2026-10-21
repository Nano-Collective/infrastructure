# Repositories, and the rulesets and labels that belong to each.

module "repository" {
  source   = "./modules/repository"
  for_each = local.repos

  repo         = each.value
  base_labels  = local.labels.base
  extra_labels = try(local.labels.extra[each.key], [])
}

# --------------------------------------------------------------- teams --

# Split in two because a for_each resource cannot reference itself: a child team
# pointing at its parent through github_team.this[...] is a cycle even when no
# team has a parent. Root teams are created first, children second.
resource "github_team" "root" {
  for_each = { for k, v in local.teams : k => v if try(v.parent, null) == null }

  name        = each.value.name
  description = try(each.value.description, null)
  privacy     = each.value.privacy

  lifecycle {
    # Deleting a team silently removes everyone's access to every repository it
    # grants, and a code owner that no longer exists satisfies a code owner
    # review vacuously. Delete the file, read the plan, then lift this.
    prevent_destroy = true
  }
}

resource "github_team" "child" {
  for_each = { for k, v in local.teams : k => v if try(v.parent, null) != null }

  name           = each.value.name
  description    = try(each.value.description, null)
  privacy        = each.value.privacy
  parent_team_id = github_team.root[each.value.parent].id

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_team_repository" "this" {
  for_each = local.team_grants

  team_id    = local.team_ids[each.value.team]
  repository = module.repository[each.value.repository].name
  permission = each.value.permission
}

resource "github_team_members" "this" {
  for_each = local.teams

  # team_slug rather than team_id: the id form is deprecated. Depending on the
  # resource rather than the catalogue keeps the ordering right, so the team
  # exists before anyone is put in it.
  team_slug = local.team_slugs[each.key]

  dynamic "members" {
    for_each = local.team_members[each.key].maintainers
    content {
      username = members.value
      role     = "maintainer"
    }
  }

  dynamic "members" {
    for_each = local.team_members[each.key].members
    content {
      username = members.value
      role     = "member"
    }
  }
}

# ---------------------------------------------------------- membership --

resource "github_membership" "this" {
  for_each = local.people

  username = each.value.github
  role     = each.value.org_role == "owner" ? "admin" : "member"

  # false means a destroy removes them from the organisation rather than
  # downgrading them, which strips every repository they could push to.
  downgrade_on_destroy = false
}

# ------------------------------------------------- organisation settings --

# Off by default. See the comment on var.manage_org_settings for why, and read
# it before turning this on.
resource "github_organization_settings" "this" {
  count = var.manage_org_settings ? 1 : 0

  billing_email = var.billing_email
  name          = local.org.name
  description   = trimspace(local.org.description)
  blog          = local.org.blog
  email         = local.org.email

  default_repository_permission = local.org.default_repository_permission

  members_can_create_repositories         = local.org.members_can_create_repositories
  members_can_create_public_repositories  = local.org.members_can_create_repositories
  members_can_create_private_repositories = local.org.members_can_create_repositories

  web_commit_signoff_required = local.org.web_commit_signoff_required

  dependabot_alerts_enabled_for_new_repositories               = local.org.security_defaults.dependabot_alerts
  secret_scanning_enabled_for_new_repositories                 = local.org.security_defaults.secret_scanning
  secret_scanning_push_protection_enabled_for_new_repositories = local.org.security_defaults.secret_scanning_push_protection
  advanced_security_enabled_for_new_repositories               = local.org.security_defaults.advanced_security
}
