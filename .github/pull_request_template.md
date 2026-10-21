## What this changes

<!-- One sentence. If it needs more than one, consider two pull requests: the
     plan is the review, and a plan nobody can read is not a gate. -->

## Why

<!-- The reasoning, not the mechanics. The diff already shows the mechanics. -->

## Checklist

- [ ] One change. No refactor bundled in.
- [ ] `./policy/checks.sh` passes locally.
- [ ] A new ruleset starts at `enforcement: evaluate`, not `active`.
- [ ] No ruleset has an empty `bypass_actors`.
- [ ] If this widens access, it was raised as an issue or in Discord first.
- [ ] If `manage_labels` is being turned on, the existing labels worth keeping
      are folded into `org/labels.yaml` in this same pull request.

## Plan

<!-- A plan is commented here automatically once this is out of draft, and
     again on every push. A reviewer should read the plan, not just the diff.
     Paste anything from it that deserves attention. Comment /plan to run it
     again. -->
