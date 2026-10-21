# The two shared rulesets, defined once.
#
# GitHub Free has no organisation-level rulesets, so the same definition has to
# reach every repository one at a time.
#
# Two rulesets rather than one because bypass is all or nothing per ruleset.
# Split, review is bypassable by maintainers -- who cannot approve their own
# pull request -- and the status checks are not.

locals {
  # The six blocking checks as the reusable workflow reports them: a job called
  # through a reusable workflow reports as "<caller job> / <job name>". The bare
  # name matches nothing, and nor does the longer string the rulesets UI shows.
  # Get this wrong and nothing merges, forever.
  required_checks = [
    "pr-checks / Linting",
    "pr-checks / Type Checks",
    "pr-checks / Format Checks",
    "pr-checks / Unused Dependencies",
    "pr-checks / Unit Tests & Coverage Analysis",
    "pr-checks / Verify Build",
  ]

  # GitHub Actions. The context alone is not enough: without the app id, a
  # third party could in principle report a check by the same name.
  github_actions_app_id = 15368

  # RepositoryRole bypass ids are undocumented and not ordered by privilege.
  # Found by probing: 2 = maintain, 4 = write, 5 = admin. Every other id from
  # 1 to 12 is refused with "Actor base role does not have write permissions".
  role_maintain = 2

  # Zero, not one. OrganizationAdmin is a role, not an actor, so GitHub stores
  # null for its actor_id and the provider reads it back as 0. The provider
  # documentation suggests 1; write 1 and the plan shows the same one-line
  # change forever.
  org_admin_actor_id = 0

  quality = try(var.repo.rulesets.quality, null)
  review  = try(var.repo.rulesets.review, null)
}

resource "github_repository_ruleset" "quality" {
  count = local.quality == null ? 0 : 1

  name        = "Quality gates"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = local.quality.enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Organisation admins only, and it is break glass. Never leave this list
  # empty: that means nobody, including the scheduled jobs that push badges and
  # changelogs to their own repository.
  bypass_actors {
    actor_id    = local.org_admin_actor_id
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    required_status_checks {
      strict_required_status_checks_policy = false
      do_not_enforce_on_create             = false

      dynamic "required_check" {
        for_each = local.required_checks
        content {
          context        = required_check.value
          integration_id = local.github_actions_app_id
        }
      }
    }
  }
}

resource "github_repository_ruleset" "review" {
  count = local.review == null ? 0 : 1

  name        = "Review gates"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = local.review.enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = local.org_admin_actor_id
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  # Anyone at maintain. This is the half that maintainers can step around, so
  # that a maintainer merging their own work does not need to find a second
  # person first. They still cannot merge red.
  bypass_actors {
    actor_id    = local.role_maintain
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    pull_request {
      required_approving_review_count   = 1
      require_code_owner_review         = true
      required_review_thread_resolution = true
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = false
      allowed_merge_methods             = ["merge", "squash", "rebase"]
    }

    # Recorded per repository rather than forced on, so turning it on is its own
    # pull request.
    dynamic "copilot_code_review" {
      for_each = try(local.review.copilot_code_review, false) ? [1] : []
      content {
        review_draft_pull_requests = false
        review_on_push             = false
      }
    }
  }
}
