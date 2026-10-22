# Reading the catalogue: the YAML under repos/, teams/ and people/ is the whole
# input.

locals {
  catalogue_root = "${path.module}/.."

  repos = {
    for f in fileset("${local.catalogue_root}/repos", "*.yaml") :
    yamldecode(file("${local.catalogue_root}/repos/${f}")).name =>
    yamldecode(file("${local.catalogue_root}/repos/${f}"))
  }

  teams = {
    for f in fileset("${local.catalogue_root}/teams", "*.yaml") :
    yamldecode(file("${local.catalogue_root}/teams/${f}")).slug =>
    yamldecode(file("${local.catalogue_root}/teams/${f}"))
  }

  people = {
    for f in fileset("${local.catalogue_root}/people", "*.yaml") :
    yamldecode(file("${local.catalogue_root}/people/${f}")).github =>
    yamldecode(file("${local.catalogue_root}/people/${f}"))
  }

  org    = yamldecode(file("${local.catalogue_root}/org/settings.yaml"))
  labels = yamldecode(file("${local.catalogue_root}/org/labels.yaml"))

  # One lookup for a team id regardless of which half of github_team created
  # it, so nothing downstream has to care about the root and child split.
  team_ids = merge(
    { for k, v in github_team.root : k => v.id },
    { for k, v in github_team.child : k => v.id },
  )

  team_slugs = merge(
    { for k, v in github_team.root : k => v.slug },
    { for k, v in github_team.child : k => v.slug },
  )

  # One entry per team and repository pair, which is the shape
  # github_team_repository wants.
  #
  # `all_repositories` is expanded here because GitHub has no blanket grant: the
  # API is strictly per repository and the Free plan has nothing at org level.
  team_grants = merge([
    for slug, team in local.teams : merge(
      try(team.all_repositories, null) == null ? {} : {
        for repo, _ in local.repos :
        "${slug}:${repo}" => { team = slug, repository = repo, permission = team.all_repositories }
      },
      # Named repositories are merged last, so one can be held at a different
      # permission from the blanket without the blanket having to know.
      {
        for repo, permission in try(team.repositories, {}) :
        "${slug}:${repo}" => { team = slug, repository = repo, permission = permission }
      },
    )
  ]...)

  # Inverted from people/, so that a person's file is the single place their
  # access is written down and the team file does not have to repeat it.
  #
  # lower() because github_team_members reads a login back lowercased while
  # person.github holds it as GitHub spells it, and the provider compares the
  # two as plain strings. A login with capitals therefore plans forever: the
  # apply writes `addyCooks`, the next read returns `addycooks`, and the
  # difference is a remove-and-add that applies cleanly and changes nothing.
  # That is what the 2026-10-22 apply hit -- it succeeded, and the plan after
  # it still wanted one change.
  #
  # Lowering here rather than in the YAML keeps `github:` canonical, which is
  # what schema/person.schema.json asks for and what github_membership and the
  # read-back both want. GitHub logins are case-insensitive, so this narrows
  # nothing. `Avtrkrb` is the only other capitalised login and is in no team;
  # without this, adding them to one would reopen the same loop.
  team_members = {
    for slug, team in local.teams : slug => {
      members = [
        for login, person in local.people : lower(login)
        if contains([for t in try(person.teams, []) : t.team], slug)
        && [for t in person.teams : t.role if t.team == slug][0] == "member"
      ]
      maintainers = [
        for login, person in local.people : lower(login)
        if contains([for t in try(person.teams, []) : t.team], slug)
        && [for t in person.teams : t.role if t.team == slug][0] == "maintainer"
      ]
    }
  }
}
