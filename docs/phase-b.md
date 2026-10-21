# Phase B: the queue

Phase A recorded what the organisation is. The first plan reports no changes,
which is the only reason anything here is safe to apply.

Phase B is everything the catalogue now makes visible and nobody had decided
on. Each line is its own pull request with its own small plan. Nothing here is
urgent, and nothing here should be bundled.

The order matters, and in one place it is not obvious. The import is armed
(`var.bootstrap`) for exactly one apply, and while it is armed every import
block is driven by the catalogue rather than by what GitHub has. So the
catalogue can **record** things that already exist and cannot **add** things
that do not. `repos/infrastructure.yaml` falls on the wrong side of that: by the
time CI can run at all the repository exists, so it has to be recorded while the
import is armed, not added after it is off.

Which fixes the order of the first three:

1. First apply. Sixty-three imports, nothing else.
2. Record `repos/infrastructure.yaml`, still armed, so it imports.
3. Disarm. From then on the catalogue can grow.

## First, because nothing else works without it

- [ ] **Create the two GitHub Apps** and install them. `nc-infra-plan` reads:
      administration, members, metadata, and **organisation secrets**, which is
      the one that is easy to miss — without it the nightly job cannot list
      secret names and `./policy/checks.sh --require-secrets` fails on
      permissions rather than on a missing secret. `nc-infra-apply` writes:
      administration, members, metadata, organisation administration.
- [ ] **Create the R2 bucket**, and one environment. `production`, with the core
      team as required reviewers, gates every apply and holds
      `NC_INFRA_APPLY_APP_ID` and `NC_INFRA_APPLY_PRIVATE_KEY` and nothing else.
      Everything a read needs — `NC_INFRA_PLAN_*`, `R2_*`,
      `CLOUDFLARE_ACCOUNT_ID` — goes in repository secrets, because all three
      workflows read and only one writes.
- [ ] **Push, plan, apply.** Sixty-three imports, nothing added, changed or
      destroyed. Nothing below starts until that has gone through.
- [ ] **Add `repos/infrastructure.yaml`**, while the import is still armed. It
      is deliberately absent today, because the repository does not exist yet
      and a file for a repository that is not there makes the first plan
      non-empty.

      Write it from what the repository actually is rather than from what it
      ought to be: it is being imported, not created, so a description or a
      merge setting that does not match is a change smuggled into a recording.
      `whitepaper_exempt: infrastructure`. Do not give `core-team` access to it
      in the same pull request — that grant does not exist yet, so it is an
      addition, and additions come after the next item.
- [ ] **Set `var.bootstrap` to `false`** in `tofu/imports.tf`. That plan must
      report no changes.

      This one is a prerequisite for everything below it, not tidying. Every
      import block is driven by the catalogue rather than by what GitHub has, so
      while it is armed a newly named repository, person or team grant has
      nothing to import and the plan dies with `Cannot import non-existent
      remote object`. In other words: armed, the catalogue can record what
      exists but cannot add anything. `./policy/checks.sh` warns on every run
      until this is done.

## Security follow-ups

Tracked privately, not here. An open list of this repository's own weaknesses,
with the consequence of each spelled out, is a roadmap for anybody who wants to
use them, and this repository is public.

The hardening that is already in place is visible in the files themselves:
`policy/checks.sh` refuses provisioners, remote modules and a redirected
provider; `plan.yml` refuses pull requests from forks and takes its gate files
and lock file from the default branch; no variable can carry a credential.

## The drift the catalogue found

Each of these is a real difference nobody decided on.

- [ ] **Five repositories carry no ruleset at all:** `docs`, `nanolist`,
      `roster`, `.github`, `taskforest`. `taskforest` cannot have one, because
      it is private and the plan is Free. The other four can. Start with
      `docs`, which has the least traffic. Go in at `evaluate`, read a day of
      rule suites, flip to `active` in a second pull request.
- [ ] **Two repositories have Review gates but not Quality gates:**
      `contentforest` and `organisation`. Both can merge a failing suite
      behind one approval.
- [ ] **Three of the nine with Review gates have no automated code review:**
      `nanocoder`, `nanotune`, `prompt-scrubber`. The other six do. Decide
      which is right and make them match.
- [ ] **Four repositories have no CODEOWNERS**, and two more name an owner that
      does not resolve. Review gates requires a code-owner review, which is
      satisfied vacuously when there is no owner, so this matters wherever that
      ruleset is applied. **Outside the scope of this repository:** closing it
      is a pull request on each one, opened by a person. The specifics are in
      the private follow-up list rather than here.
- [ ] **`core-team` reaches 9 of 14 repositories:** everything except
      `contentforest`, `nanolist`, `organisation`, `roster` and `taskforest`.
      Nobody chose those five. If the answer is that the core team should reach
      everything, it is one line — replace the `repositories:` block in
      `teams/core-team.yaml` with `all_repositories: maintain`, which also
      covers every repository added afterwards without anyone remembering to
      come back here. Expect a plan of exactly five additions. Its own pull
      request, because it widens access and `CONTRIBUTING.md` says so.

      It was deliberately not bundled with the import: the first apply is 63
      imports and nothing else, so that if it goes wrong there is only one kind
      of thing it can have gone wrong at.
- [ ] **`nanoterm` has no description.** It is public.
- [ ] **The `admin` team grants access to nothing** and duplicates
      organisation ownership. Delete it or give it a job.
- [ ] **Three people are organisation owners with no reason recorded.** An
      owner can change anything, including the rulesets protecting this
      repository.

## The governance change

- [ ] **One `<project>-maintainers` team per project**, holding `maintain`,
      named as a code owner alongside `core-team`, by a human. This is in the
      whitepaper
      because it widens who can merge. Do not start it until the whitepaper
      has been through its window.

      There was a `maintainer_team` field on the repository schema for this. It
      has been removed: nothing read it, so a repository file could name a
      maintainer team and no team and no grant would appear. A field that
      silently does nothing is worse than no field. When this change happens it
      needs a team file and a grant, which already work, and the schema can gain
      a field then if one turns out to help.

## Turning on the parts held back

- [ ] **`manage_labels`, one repository at a time.** Opting in deletes every
      label not in `org/labels.yaml`. `nanocoder` has 50. Fold the useful ones
      in first, in the same pull request. Start with `json-up`, which has the
      default set and nothing else.

      Two colours in `org/labels.yaml` were wrong and would have failed here
      rather than at review: unquoted, `5319e7` is scientific notation to a YAML
      parser and decodes as `53190000000`, and `008672` decodes as `8672`.
      OpenTofu's `yamldecode` agrees. Every colour is quoted now and the
      validator rejects anything that is not six lowercase hex digits.
- [ ] **`manage_org_settings`.** Record `billing_email` and the fields the
      resource sets that the catalogue does not yet name, then flip the
      variable. Read that plan carefully: the resource is all or nothing.
- [ ] **Organisation security defaults.** Dependabot alerts, secret scanning
      and push protection are all off for new repositories. They are free for
      public repositories.

## Retiring what this replaces

Only once the above is done and a month of nightly drift checks have been
quiet.

- [ ] **Retire the earlier ruleset tooling**, leaving a pointer here.
- [ ] **Rewrite the rulesets section of
      `docs/content/collective/projects/project-infrastructure.md`** to
      describe this repository.

## Questions the catalogue raised and does not answer

- Nothing documents how a person leaves. Sponsor offboarding is written down in
  detail; human offboarding is not. Deleting a file in `people/` is now the
  mechanism. What should trigger it is a governance question.
- `branding` has no remote at all and `docforest` has a remote with nothing in
  it. Neither is in the organisation's repository list. Decide what they are.
