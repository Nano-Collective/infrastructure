# Contributing

This repository configures the Nano Collective's GitHub organisation. A merged
change here changes who can do what, so it is reviewed a little more carefully
than a typo fix in a README. The process is still just a pull request.

Please read the collective's
[Code of Conduct](https://docs.nanocollective.org/collective/organisation/community)
and [Governance](https://docs.nanocollective.org/collective/organisation/governance)
first. They apply here as they do everywhere else.

## Before you start

**Small and self-contained: just open the pull request.** Adding a topic,
fixing a description, recording something that is already true. No need to ask.

**Anything that widens access: raise it first.** Adding an organisation owner,
giving a team access to a new repository, weakening a ruleset, removing
somebody. Open an issue, or ask in Discord, before you write the file. Not
because the answer will be no, but because the reasoning belongs in public and
a pull request is a poor place to have the conversation for the first time.

## The three stages

**Validate** runs on every pull request, including from a fork. It checks each
file against its schema, checks that every name refers to something that
exists, applies the rules a schema cannot express, and asks the docs site
whether the whitepaper you named has been approved. It holds no credentials.

**Plan** runs when somebody with write access comments `/plan`, and only on a
branch of this repository. It does not run automatically, and **it does not run
on pull requests from forks at all**.

The reason is worth understanding, because it is the one real security boundary
here. A plan executes this repository's configuration: `tofu init` fetches
whatever modules and providers the configuration names, and a provider plugin is
an arbitrary executable. That happens in a job holding a token and the state
credentials. Screening the configuration first does not help, because a fork can
edit the thing doing the screening.

So forks get Validate, which holds no credentials and is what review actually
needs. If your change should be planned, ask a maintainer to push the commits to
a branch here — that is a deliberate act of adoption, which is the point.

**Apply** runs after the merge, and waits. The job queues against the
`production` environment, where the core team are required reviewers, and
somebody presses the button. Two humans in total: one approved the pull
request, one released the apply.

## Running the checks locally

```sh
pnpm install
./policy/checks.sh            # everything
./policy/checks.sh --offline  # skip the parts that need the network
./policy/checks.sh --guard    # just the secret guard
```

Turn on the pre-commit hook once per clone. It runs `--guard`, which refuses a
commit that stages a credential-bearing file or a token-shaped string:

```sh
git config core.hooksPath .githooks
```

That is a convenience, not a gate — `--no-verify` skips it and a fresh clone
does not have it. The gate is the same check in Validate, and secret scanning
with push protection on the repository itself.

To see a plan:

```sh
cd tofu
cp backend_override.tf.example backend_override.tf
tofu init -reconfigure
GITHUB_TOKEN=$(gh auth token) tofu plan
```

Plan locally. Apply in CI. A local apply writes to a state file CI knows
nothing about, and the next CI apply will try to undo whatever you did.

## Things that will fail review

**A ruleset going straight in at `active`.** Start at `evaluate`, read a day of
rule-suite results, then flip it in a second pull request. Enforcing a check
that is not yet reporting makes every open pull request in that repository
permanently unmergeable, and it reads as a broken workflow rather than as a
ruleset somebody enabled that morning.

**An empty bypass list.** `bypass_actors: []` means nobody, including the
scheduled jobs that push badges and changelogs to their own repository. Those
then start failing with no obvious connection to the change. Keep the
organisation admin bypass.

**Naming an individual where a team would do.** Access is granted to teams, in
`teams/`, and membership is recorded in `people/`. Adding a maintainer should
be one membership change, not a change in several places.

**Anything that writes into another repository.** This repo configures GitHub.
It does not touch repository contents: no files, no workflows, no CODEOWNERS.
That boundary is in the whitepaper and is not a staging decision.

**A change bundled with a refactor.** One pull request, one change, one
readable plan. The plan is the review; a plan nobody can read is not a gate.

**Turning on `manage_labels` without folding the existing labels in first.**
Opting a repository in deletes every label not listed in `org/labels.yaml`.
`nanocoder` has 50. Fold the useful ones in first, in the same pull request.

## Commit messages

The same convention as the rest of the collective. Lowercase, imperative mood,
no trailing full stop. `feat:`, `fix:`, `mod:` for a change to existing
behaviour, `chore:`, `docs:`. Scope in parentheses is optional.

```
feat(repos): add quality gates to docs in evaluate mode
mod(teams): give core-team maintain on nanolist
docs: explain why org settings are described but not driven
```

## Questions

Open an issue, or ask in [Discord](https://discord.gg/ktPDV6rekE).
