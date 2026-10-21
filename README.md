# Infrastructure

This repository is the Nano Collective's GitHub organisation, written down.

Every repository, team, ruleset and membership is a file here. Change a file,
open a pull request, and a machine shows you exactly what would move before
anyone agrees to it. Nothing is configured by hand in a web form that only one
person remembers visiting.

It is public for the same reason the rest of the collective's documentation is
public. Anyone can read who has access to what, and why.

## Why this exists

The collective had already decided that the merge gate should be automated
rather than human, and had already put its shared workflows in one place. The
GitHub configuration those workflows depend on is still applied by hand, one
repository at a time, because the Free plan has no organisation-level
rulesets. Here is what that costs, measured on the live organisation on
2 October 2026:

| | State |
| --- | --- |
| Both rulesets applied | 7 of 14 repositories |
| One ruleset only | 2 |
| No rulesets at all | 5 |
| Automated review on pull requests | 6 of the 9 with Review gates |

None of that is anybody's fault. It is what hand-applied configuration looks
like after a year. A script somebody remembers to run is not a gate.

## How to change something

Three steps, and you do not need to know OpenTofu for any of them.

1. **Edit a file.** Repositories are in `repos/`, teams in `teams/`, people in
   `people/`. One file each, plain YAML.
2. **Open a pull request.** The Validate job checks the shape of your file,
   the names it refers to, and the rules that are not about shape. It takes
   seconds and holds no credentials.
3. **Read the plan.** A bot comments the exact list of changes on the pull
   request, in a dropdown, as soon as it is out of draft and again on every
   push. Anybody with write access can comment `/plan` to run it again. A core
   team member approves the pull request, and after the merge a second one
   releases the apply.

Two humans see every change, and both of them see the plan first.

**Pull requests from forks are validated but not planned.** A plan runs this
repository's configuration — including any module or provider it names — in a
job holding credentials, and there is no safe way to do that with a branch this
repository does not control. Validate still runs on your fork and holds nothing,
and it is the part that matters for review. If a change should be planned, a
maintainer pushes the same commits to a branch here and plans that.

### Asking for a new repository

Add one file to `repos/`. The smallest useful version:

```yaml
name: my-project
description: One sentence saying what it does and who it is for.
homepage: https://docs.nanocollective.org/my-project
visibility: public
archived: false
vulnerability_alerts: true
default_branch: main

topics: [cli, local-first]

features:
  issues: true
  projects: false
  wiki: false
  discussions: false

merge:
  squash: true
  merge_commit: false
  rebase: false
  auto_merge: false
  delete_branch_on_merge: true

# Start at evaluate. Read a day of results. Flip to active in a second pull
# request. Enforcing a check that is not yet reporting makes every open pull
# request in the repository unmergeable, and it looks like a broken workflow
# rather than a ruleset somebody turned on.
rulesets:
  quality:
    enforcement: evaluate
  review:
    enforcement: evaluate
    copilot_code_review: true

manage_labels: true

whitepaper: my-project
```

Who can reach it is not in that file. Access is granted by a team, and a team
is a file in `teams/`, so there is one place to look rather than fourteen.

CI reads `whitepaper` against the live manifest at
`docs.nanocollective.org/whitepapers.json` and refuses unless that whitepaper
says `Build approved`. That is the step the collective's own project pipeline
calls for, and it is the reason a repository cannot appear without having gone
through public review. A repository that genuinely has no whitepaper, such as
this one, sets `whitepaper_exempt` instead and says which of three reasons
applies.

### Joining a project

Change your file in `people/`. Add the team to your `teams` list. The core team
reviews it. That is the whole mechanism.

### Giving a team access

A team file in `teams/` either names repositories one at a time:

```yaml
repositories:
  nanocoder: maintain
  sentinel: maintain
```

or names a permission once and holds it on everything:

```yaml
all_repositories: maintain
```

`all_repositories` covers every repository in `repos/`, including ones added
later, so a new project is reachable the day its file lands and nobody has to
remember to come back here. GitHub has no such grant of its own — the API is
strictly one repository at a time, and the Free plan has nothing at the
organisation level either — so this is expanded per repository when the plan
runs. The plan shows each grant separately, which is the point: a blanket in the
file still reads as fourteen lines in the thing a human approves.

Both can appear together. `repositories` is applied last, so a named repository
can be held at a different permission from the blanket.

## What this manages, and what it does not

**It manages GitHub configuration, and only that:** repository settings,
topics and features; the two rulesets; Dependabot alerts; labels, for the
repositories that have opted in; teams and who is in them; which teams can
reach which repositories; organisation membership and who is an owner.

**It does not reach inside a repository.** No source, no workflows, no issue
templates, no CODEOWNERS. What a project contains is the project's business,
and the shared workflows already cover the parts that should be the same
everywhere. There is a mechanical reason too: writing a
file into a repository commits straight to the default branch, which both
rulesets block, so doing it would mean giving this automation a bypass on
Quality gates.

One consequence worth knowing. Review gates requires a code-owner review, which
is satisfied vacuously when a repository has no CODEOWNERS, and four have none.
This repo applies the ruleset; it does not write that file. Closing the gap is
a pull request on each repository, opened by a person.

**It does not hold secret values.** `org/secrets.yaml` lists which
organisation secrets must exist and at what visibility. No value appears in
this repository or in the state file. An owner sets each one by hand, and CI
checks the name still exists.

**It does not drive organisation settings yet.** `org/settings.yaml` describes
them and CI reads the live organisation back and fails when it moves, but
nothing applies them. The reason is in `tofu/variables.tf` under
`manage_org_settings`, and so is the path to turning it on.

**It does not replace Sentinel.** A plan is authoritative for anything in the
catalogue: it reports an exact diff and can correct it. Sentinel audits what a
catalogue cannot see, such as whether a repository's tests prove anything.
One asks whether this matches the file. The other asks whether it is any good.

## Two constraints worth knowing

**The organisation is on GitHub Free.** That has no organisation-level
rulesets, so the same definition is written to every repository one at a time.
It also refuses rulesets on private repositories, which is why `taskforest` has
none and why the schema rejects one if you try.

**Required check contexts carry a prefix.** A job called through a reusable
workflow reports as `pr-checks / Linting`, not `Linting`. The bare name matches
nothing, and neither does the longer string the rulesets interface displays,
which is a display label. Get it wrong and the repository reports
"6 of 6 required status checks are expected" forever and nothing merges.

## Running it yourself

A plan is read only and you are welcome to run one.

```sh
pnpm install
./policy/checks.sh                 # schema, references, policy, read-back

cd tofu
cp backend_override.tf.example backend_override.tf
tofu init -reconfigure
GITHUB_TOKEN=$(gh auth token) tofu plan
```

Plan locally, apply in CI. An apply from a laptop writes to a state file CI
knows nothing about, and the next CI apply will try to undo it.

## Layout

```
org/        organisation settings, the base label set, required secret names
repos/      one file per repository
teams/      one file per team, and which repositories it can reach
people/     one file per member, and which teams they are in
schema/     JSON Schema for each of the three file types
policy/     one command that runs every check
scripts/    the validator, the read-back and the importer
tofu/       the OpenTofu configuration that reads all of the above
```

## One thing a plan cannot tell you

A clean plan means "nothing I manage has moved". It does not mean "the
organisation matches these files", and the gap between those two is worth
knowing about.

Repositories, organisation memberships and team grants are each managed one at a
time, because that is the only shape GitHub's API offers. So a repository
created by hand, a person invited by hand, or a team given access by hand is not
drift as far as OpenTofu is concerned — it is outside the world, and the plan
reports no changes without ever having looked at it.

This is not hypothetical. `core-team` was granted `maintain` on `docs` shortly
after the import, the catalogue stayed at eight grants, and every plan said "No
changes" and was telling the truth about the eight things it knew.

`scripts/readback.mjs` is what closes that. It asks GitHub for the whole list
each time and fails on anything live that no file claims. It runs as part of
`./policy/checks.sh`, and the nightly drift job runs both, so the issue it opens
covers both kinds of difference.

## Questions

Open an issue here, or ask in [Discord](https://discord.gg/ktPDV6rekE).

The design and the reasoning behind it are in the whitepaper at
[docs.nanocollective.org/collective/whitepapers/infrastructure](https://docs.nanocollective.org/collective/whitepapers/infrastructure).
