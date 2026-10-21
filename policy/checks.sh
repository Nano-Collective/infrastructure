#!/usr/bin/env bash
#
# checks.sh - one command that says whether a change is safe to plan.
#
# Runs with no credentials and no network beyond the docs manifest. Three parts:
#   1. The OpenTofu config is well formed and executes nothing.
#   2. The catalogue is valid and self-consistent (scripts/validate.mjs).
#   3. The organisation matches it (scripts/readback.mjs).
#
# Usage:
#   ./policy/checks.sh                   # all of it
#   ./policy/checks.sh --offline         # skip anything needing the network
#   ./policy/checks.sh --guard           # only the secret guard, for the hook
#   ./policy/checks.sh --require-secrets # online, and a secret that cannot be
#                                        # listed is a failure rather than a warning

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OFFLINE=0
GUARD_ONLY=0
REQUIRE_SECRETS=""
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=1 ;;
    --guard) GUARD_ONLY=1 ;;
    --require-secrets) REQUIRE_SECRETS="--require-secrets" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

rc=0
fail() { echo "FAIL  $*" >&2; rc=1; }
pass() { echo "ok    $*"; }

# ------------------------------------------------------- 0. secret guard --
#
# The one mistake a public repository cannot take back: a commit is reachable by
# sha forever, even after a force-push. This reads the git index, so the same
# code is the pre-commit hook (.githooks/pre-commit) and the CI gate -- in CI
# the index is the commit, in the hook it is what is about to become one.
#
# Only file names are ever printed. Printing a matched line would put the
# credential into a public Actions log, which is the thing being prevented.

bad_names=$(git -C "$ROOT" ls-files \
  | grep -EI '(^|/)(\.env(\..+)?|\.envrc|\.terraformrc|terraform\.rc|\.tofurc|tofu\.rc|tfplan|plan\.json|override\.tf|override\.tf\.json|id_rsa|id_ed25519)$|\.(tfstate|tfplan|pem|key|p12|pfx)$|_override\.tf(\.json)?$' \
  || true)
if [ -n "$bad_names" ]; then
  echo "$bad_names" | sed 's/^/      /' >&2
  fail "a file that can carry a credential is tracked. Remove it from the index: git rm --cached <file>"
else
  pass "no credential-bearing filenames are tracked"
fi

# Token shapes, matched against the index. This file and the hook are excluded
# because they contain the patterns themselves.
token_shapes='gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{32,}'
leaky=$(git -C "$ROOT" grep --cached -l -IE "$token_shapes" \
  -- . ':!policy/checks.sh' ':!.githooks/pre-commit' || true)
if [ -n "$leaky" ]; then
  echo "$leaky" | sed 's/^/      /' >&2
  fail "a tracked file contains something shaped like a credential. The file names are above; the matching lines are deliberately not printed."
else
  pass "no token-shaped strings in tracked files"
fi

if [ "$GUARD_ONLY" -eq 1 ]; then
  if [ "$rc" -eq 0 ]; then echo "Secret guard passed."; else echo "Secret guard failed."; fi
  exit "$rc"
fi

# ------------------------------------------------- 1. the OpenTofu config --

# Every extension OpenTofu will load. .tofu and the .json forms count: a check
# that only reads *.tf is one rename away from seeing nothing.
tf_src=(--include='*.tf' --include='*.tf.json' --include='*.tofu' --include='*.tofu.json')

# A plan executes the configuration, so a provisioner or an external data source
# would run code on the runner with whatever the plan job holds. Nothing here
# needs any of them. Both the HCL and the JSON spelling of each.
banned='provisioner[[:space:]"]|"provisioner"|data[[:space:]]+"(external|http)"|"(external|http)"[[:space:]]*:|local-exec|remote-exec'
if grep -rInE "$banned" "$ROOT/tofu" "${tf_src[@]}" >/dev/null 2>&1; then
  grep -rInE "$banned" "$ROOT/tofu" "${tf_src[@]}" >&2
  fail "the OpenTofu config runs code. Provisioners and external data sources are not allowed here."
else
  pass "no provisioners or external data sources"
fi

# Every module and provider source must be a local path or integrations/github.
# A remote module is fetched by `tofu init` and the grep above cannot see inside
# it; a new provider is an executable that init downloads and plan runs. Either
# should be a deliberate change to this line and to the lock file.
remote_modules=$(grep -rInE '^\s*source\s*=\s*"' "$ROOT/tofu" "${tf_src[@]}" \
  | grep -vE '^\S+:\s*[0-9]+:\s*source\s*=\s*"\.{1,2}/' \
  | grep -vE 'required_providers|^\S+:[0-9]+:\s*source\s*=\s*"integrations/github"' || true)
if [ -n "$remote_modules" ]; then
  echo "$remote_modules" >&2
  fail "a module or provider source is neither a local path nor integrations/github. A remote module is fetched at init time and nothing here can see inside it; a new provider is an executable that plan would run."
else
  pass "every module and provider source is local or the one known provider"
fi

# A ruleset with no bypass actor blocks everybody, including the scheduled jobs
# that push badges and changelogs to their own repository. Checked per resource
# rather than by grepping for an empty list, because the list is written as a
# block and `bypass_actors = []` is not a spelling this file would ever use.
naked=$(awk '
  /^resource "github_repository_ruleset"/ {
    if (name != "" && !seen) print name
    name = $3; seen = 0; next
  }
  /^[[:space:]]*bypass_actors[[:space:]]*\{/ { seen = 1 }
  END { if (name != "" && !seen) print name }
' "$ROOT/tofu/modules/repository/rulesets.tf")
if [ -n "$naked" ]; then
  echo "$naked" | sed 's/^/      /' >&2
  fail "a ruleset has no bypass actor. Keep the organisation admin bypass."
else
  pass "every ruleset keeps a bypass actor"
fi

# The provider must not be redirected. plan.yml restores policy/ and scripts/
# from the default branch before executing anything, but not tofu/, so a branch
# on this repository can still edit providers.tf. base_url would send the plan
# job's App token to another host, and an inline token attribute would bypass
# the environment entirely.
redirected=$(grep -rInE '^[[:space:]]*(base_url|insecure|cache_path|token)[[:space:]]*=' \
  "$ROOT/tofu" "${tf_src[@]}" || true)
if [ -n "$redirected" ]; then
  echo "$redirected" >&2
  fail "the provider is being redirected or handed a token in the configuration. The token comes from GITHUB_TOKEN in the environment, and base_url must not be set."
else
  pass "the provider is not redirected and carries no inline token"
fi

# The R2 endpoint carries the account id, and a saved plan serialises the whole
# backend configuration. apply.yml publishes that plan as a build artifact on a
# public repository, so the endpoint has to stay in AWS_ENDPOINT_URL_S3 and out
# of both the backend block and -backend-config. See tofu/backend.tf.
endpoint_cfg=$(grep -rInE '^[[:space:]]*endpoints?[[:space:]]*=' "$ROOT/tofu" "${tf_src[@]}" || true)
endpoint_flag=$(grep -rn 'backend-config' "$ROOT/.github/workflows" 2>/dev/null || true)
if [ -n "$endpoint_cfg$endpoint_flag" ]; then
  printf '%s\n' "$endpoint_cfg" "$endpoint_flag" | grep -v '^$' >&2
  fail "the state endpoint is set in the configuration or at init. That records the account id in every saved plan, and apply.yml publishes the plan. Use AWS_ENDPOINT_URL_S3 on each step instead."
else
  pass "the state endpoint comes from the environment, not the saved plan"
fi

stray_provider=$(grep -rlE '^[[:space:]]*provider[[:space:]]+"' "$ROOT/tofu" "${tf_src[@]}" \
  | grep -v '/providers\.tf$' || true)
if [ -n "$stray_provider" ]; then
  echo "$stray_provider" | sed 's/^/      /' >&2
  fail "a provider block lives outside tofu/providers.tf, where nobody will look for it."
else
  pass "the only provider block is in tofu/providers.tf"
fi

# While var.bootstrap is on, every import block is driven by the catalogue, so a
# newly named repository, person or team grant has nothing to import and the plan
# dies with "Cannot import non-existent remote object". Hence a standing warning.
if grep -qE '^\s*default\s*=\s*true' <(sed -n '/variable "bootstrap"/,/^}/p' "$ROOT/tofu/imports.tf"); then
  echo "warn  the import is still armed (tofu/imports.tf, var.bootstrap). Fine until it has been applied once. After that set it to false, or the catalogue can only record and never add."
else
  pass "the import is disarmed"
fi

if ! grep -q 'prevent_destroy = true' "$ROOT/tofu/modules/repository/main.tf"; then
  fail "github_repository has lost prevent_destroy. A repository deleted by a typo is not coming back."
else
  pass "repositories carry prevent_destroy"
fi

if command -v tofu >/dev/null 2>&1; then
  if tofu -chdir="$ROOT/tofu" fmt -check -recursive >/dev/null 2>&1; then
    pass "tofu fmt"
  else
    tofu -chdir="$ROOT/tofu" fmt -check -recursive -diff || true
    fail "tofu fmt. Run: tofu -chdir=tofu fmt -recursive"
  fi
else
  echo "warn  tofu not installed, skipping fmt"
fi

# A new ruleset goes in at evaluate and is flipped to active in a second pull
# request. Enforcing a check that is not yet reporting makes every open pull
# request in that repository unmergeable.
if [ -n "${BASE_REF:-}" ] && command -v git >/dev/null 2>&1; then
  added=$(git -C "$ROOT" diff --unified=0 "origin/${BASE_REF}...HEAD" -- repos/ 2>/dev/null \
          | grep -E '^\+ +(quality|review):' || true)
  if [ -n "$added" ]; then
    ctx=$(git -C "$ROOT" diff --unified=2 "origin/${BASE_REF}...HEAD" -- repos/ 2>/dev/null \
          | grep -E '^\+ +enforcement: active' || true)
    if [ -n "$ctx" ]; then
      fail "a ruleset is being added straight at 'active'. Start at 'evaluate', read a day of rule suites, then flip it in a second pull request."
    fi
  fi
  pass "new rulesets start at evaluate"

  # Publishing a repository is one word in one file and cannot be undone: forks
  # and clones taken while it was public stay public. The plan shows it, but it
  # shows it among everything else, so say it loudly here too.
  opened=$(git -C "$ROOT" diff --unified=0 "origin/${BASE_REF}...HEAD" -- repos/ 2>/dev/null \
           | grep -E '^\+visibility: public' || true)
  if [ -n "$opened" ]; then
    echo "warn  this pull request sets a repository to 'public'. Check the plan names the repository you expect: publishing one cannot be undone, because anything cloned while it was public stays out."
  else
    pass "no repository is being made public"
  fi
fi

# --------------------------------------------------------- 2. catalogue --

if [ "$OFFLINE" -eq 1 ]; then
  node "$ROOT/scripts/validate.mjs" --offline || rc=1
else
  node "$ROOT/scripts/validate.mjs" || rc=1
fi

# ------------------------------------------- 3. the organisation itself --

# Everything above reads files. This reads GitHub, and is the only part that can
# answer "is there something out there that no file mentions".
if [ "$OFFLINE" -eq 1 ]; then
  echo "warn  offline, skipping the live organisation read-back"
else
  if [ -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
    export GITHUB_TOKEN
  fi
  node "$ROOT/scripts/readback.mjs" $REQUIRE_SECRETS || rc=1
fi

echo
if [ "$rc" -eq 0 ]; then echo "All checks passed."; else echo "Checks failed."; fi
exit "$rc"
