terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }
}

resource "github_repository" "this" {
  name         = var.repo.name
  description  = try(var.repo.description, null)
  homepage_url = try(var.repo.homepage, null)

  visibility = var.repo.visibility
  archived   = try(var.repo.archived, false)

  has_issues      = var.repo.features.issues
  has_projects    = var.repo.features.projects
  has_wiki        = var.repo.features.wiki
  has_discussions = var.repo.features.discussions

  allow_squash_merge     = var.repo.merge.squash
  allow_merge_commit     = var.repo.merge.merge_commit
  allow_rebase_merge     = var.repo.merge.rebase
  allow_auto_merge       = var.repo.merge.auto_merge
  delete_branch_on_merge = var.repo.merge.delete_branch_on_merge

  topics = try(var.repo.topics, [])

  # Nothing here writes files into another repository. Scaffolding happens as a
  # pull request, because the rulesets below block direct pushes.
  auto_init = false

  lifecycle {
    # A deleted repository is not coming back. Delete the file, read the plan,
    # then lift this line in the same pull request.
    prevent_destroy = true

    ignore_changes = [
      # Set once when the repository was created and meaningless afterwards.
      auto_init,
      # Moving the default branch is a git operation with a settings change
      # attached, so it is done by hand and recorded here afterwards.
      default_branch,
    ]
  }
}

# Dependabot alerts have their own resource; the attribute on github_repository
# is deprecated and would print a warning on every plan.
resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = var.repo.vulnerability_alerts
}

# ------------------------------------------------------------- labels --

locals {
  # The base set plus whatever org/labels.yaml lists for this repository under
  # `extra`. A repository file says whether it opts in.
  managed_labels = var.repo.manage_labels ? {
    for l in concat(var.base_labels, var.extra_labels) :
    lower(l.name) => l
  } : {}
}

resource "github_issue_label" "this" {
  for_each = local.managed_labels

  repository  = github_repository.this.name
  name        = each.value.name
  color       = each.value.colour
  description = try(each.value.description, null)
}
