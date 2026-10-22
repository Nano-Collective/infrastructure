#!/usr/bin/env node
//
// readback.mjs - ask GitHub what is actually there, and say what no file claims.
//
// OpenTofu manages three of these resources one at a time rather than as a
// complete set:
//
//   github_repository        one per file in repos/
//   github_membership        one per file in people/
//   github_team_repository   one per named grant in teams/
//
// So a repository created by hand, a person invited by hand or a team granted
// access by hand is not drift to OpenTofu; it is outside its world, and the
// plan reports "No changes". This script is what sees it.
//
// github_team_members is the exception: it manages a team's membership as a
// whole, so a hand-added member does show in a plan. It is checked here anyway.
//
// Usage:
//   GITHUB_TOKEN=... node scripts/readback.mjs
//   GITHUB_TOKEN=... node scripts/readback.mjs --require-secrets
//
// --require-secrets turns "I could not list the organisation secrets" from a
// warning into a failure. Listing them needs admin:org, or an App with
// organisation secrets read; the nightly drift job has it, a laptop may not.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const REQUIRE_SECRETS = process.argv.includes("--require-secrets");
const TOKEN = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "";

let rc = 0;
const fail = (msg) => { console.error(`FAIL  ${msg}`); rc = 1; };
const pass = (msg) => console.log(`ok    ${msg}`);
const warn = (msg) => console.log(`warn  ${msg}`);

if (!TOKEN) {
  warn("no GITHUB_TOKEN or GH_TOKEN, skipping the live read-back");
  process.exit(0);
}

// ----------------------------------------------------------- the catalogue --

const readYamlDir = (dir) => {
  const path = join(ROOT, dir);
  if (!existsSync(path)) return [];
  return readdirSync(path).filter((f) => f.endsWith(".yaml"))
    .map((f) => parseYaml(readFileSync(join(path, f), "utf8")));
};

const repos = readYamlDir("repos");
const teams = readYamlDir("teams");
const people = readYamlDir("people");
const org = parseYaml(readFileSync(join(ROOT, "org/settings.yaml"), "utf8"));
const secrets = parseYaml(readFileSync(join(ROOT, "org/secrets.yaml"), "utf8"));
const ORG = org.login;

const repoNames = repos.map((r) => r.name);

// The same expansion tofu/catalogue.tf does, for the same reason: a team with
// all_repositories reaches every repository in the catalogue, so the expected
// set of grants is not just what `repositories` names.
const expectedGrants = new Set();
for (const t of teams) {
  if (t.all_repositories) {
    for (const name of repoNames) expectedGrants.add(`${t.slug}:${name}`);
  }
  for (const name of Object.keys(t.repositories ?? {})) expectedGrants.add(`${t.slug}:${name}`);
}

// --------------------------------------------------------------- the API --

const api = async (path) => {
  const out = [];
  let url = `https://api.github.com${path}${path.includes("?") ? "&" : "?"}per_page=100`;
  while (url) {
    const res = await fetch(url, {
      headers: {
        authorization: `Bearer ${TOKEN}`,
        accept: "application/vnd.github+json",
        "x-github-api-version": "2022-11-28",
        "user-agent": "nano-collective-infrastructure",
      },
      signal: AbortSignal.timeout(30000),
    });
    if (!res.ok) {
      const e = new Error(`GET ${path} returned ${res.status}`);
      e.status = res.status;
      throw e;
    }
    const body = await res.json();
    if (Array.isArray(body)) out.push(...body); else return body;
    url = /<([^>]+)>;\s*rel="next"/.exec(res.headers.get("link") ?? "")?.[1] ?? null;
  }
  return out;
};

// ------------------------------------------------- 1. things with no file --
//
// Each of these is a live object the catalogue does not mention. Reported, not
// corrected: somebody did it on purpose.

try {
  const live = (await api(`/orgs/${ORG}/repos?type=all`)).map((r) => r.name);
  const unclaimed = live.filter((n) => !repoNames.includes(n));
  const missing = repoNames.filter((n) => !live.includes(n));
  if (unclaimed.length) {
    fail(`repositories exist with no file in repos/: ${unclaimed.join(", ")}. Nothing manages these, so nothing protects them either.`);
  }
  // A file for a repository that is not there is a different problem, and a
  // plan does catch it, but the message here is clearer than a create plan.
  if (missing.length) {
    fail(`repos/ names repositories that do not exist: ${missing.join(", ")}. A plan would try to create them.`);
  }
  if (!unclaimed.length && !missing.length) pass(`${live.length} repositories, one file each`);
} catch (e) {
  fail(`could not list repositories: ${e.message}`);
}

try {
  const live = (await api(`/orgs/${ORG}/members`)).map((m) => m.login);
  const admins = (await api(`/orgs/${ORG}/members?role=admin`)).map((m) => m.login);
  const known = people.map((p) => p.github);
  const unclaimed = live.filter((l) => !known.includes(l));
  const missing = known.filter((l) => !live.includes(l));
  if (unclaimed.length) {
    fail(`organisation members with no file in people/: ${unclaimed.join(", ")}. Nothing records what they are here for.`);
  }
  if (missing.length) {
    fail(`people/ names members who are not in the organisation: ${missing.join(", ")}.`);
  }
  // Ownership is the one that matters most and the one a per-person resource
  // is least likely to surface, so it is compared directly.
  for (const p of people) {
    const isOwner = admins.includes(p.github);
    if (isOwner && p.org_role !== "owner") {
      fail(`${p.github} is an organisation owner on GitHub but people/${p.github}.yaml says "${p.org_role}".`);
    }
    if (!isOwner && p.org_role === "owner" && live.includes(p.github)) {
      fail(`people/${p.github}.yaml says owner but GitHub has them as a member.`);
    }
  }
  if (!unclaimed.length && !missing.length) pass(`${live.length} members and ${admins.length} owners, one file each`);
} catch (e) {
  fail(`could not list organisation members: ${e.message}`);
}

try {
  const liveTeams = await api(`/orgs/${ORG}/teams`);
  const known = teams.map((t) => t.slug);
  const unclaimed = liveTeams.filter((t) => !known.includes(t.slug)).map((t) => t.slug);
  const missing = known.filter((s) => !liveTeams.some((t) => t.slug === s));
  if (unclaimed.length) fail(`teams exist with no file in teams/: ${unclaimed.join(", ")}.`);
  if (missing.length) fail(`teams/ names teams that do not exist: ${missing.join(", ")}.`);

  // The grant check. This is the one a plan is blindest to.
  const liveGrants = new Set();
  for (const t of liveTeams) {
    for (const r of await api(`/orgs/${ORG}/teams/${t.slug}/repos`)) {
      liveGrants.add(`${t.slug}:${r.name}`);
      const want = teams.find((x) => x.slug === t.slug);
      if (!want) continue;
      const expected = want.repositories?.[r.name] ?? want.all_repositories ?? null;
      // The catalogue spells permissions the way the API writes them and the
      // schema accepts: pull/push. role_name reads them back the way the web UI
      // says them: read/write. triage, maintain and admin are the same word in
      // both, which is why ten maintain grants never caught this.
      const asRoleName = { pull: "read", push: "write" };
      if (expected && (asRoleName[expected] ?? expected) !== r.role_name) {
        fail(`${t.slug} holds "${r.role_name}" on ${r.name}; teams/${t.slug}.yaml says "${expected}".`);
      }
    }
  }
  const extra = [...liveGrants].filter((g) => !expectedGrants.has(g));
  const absent = [...expectedGrants].filter((g) => !liveGrants.has(g));
  if (extra.length) {
    fail(`team access that no file grants: ${extra.join(", ")}. A plan cannot see these: github_team_repository manages one named grant at a time.`);
  }
  if (absent.length) {
    fail(`team access in the catalogue but not on GitHub: ${absent.join(", ")}.`);
  }

  // github_team_members is authoritative, so a plan would catch this too. It is
  // here so that one command answers the whole question.
  for (const t of liveTeams) {
    if (!known.includes(t.slug)) continue;
    const want = new Map(
      people.flatMap((p) => (p.teams ?? []).filter((x) => x.team === t.slug).map((x) => [p.github, x.role])),
    );
    for (const m of await api(`/orgs/${ORG}/teams/${t.slug}/members`)) {
      const membership = await api(`/orgs/${ORG}/teams/${t.slug}/memberships/${m.login}`);
      if (!want.has(m.login)) {
        fail(`${m.login} is in the team "${t.slug}" but people/${m.login}.yaml does not say so.`);
      } else if (want.get(m.login) !== membership.role) {
        fail(`${m.login} is "${membership.role}" in "${t.slug}"; people/${m.login}.yaml says "${want.get(m.login)}".`);
      }
      want.delete(m.login);
    }
    for (const [login, role] of want) {
      fail(`people/${login}.yaml claims ${role} of "${t.slug}" but GitHub does not have them in it.`);
    }
  }

  if (rc === 0) pass(`${liveTeams.length} teams, ${liveGrants.size} grants and every membership match the catalogue`);
} catch (e) {
  fail(`could not read teams: ${e.message}`);
}

// --------------------------------------------- 2. organisation settings --
//
// org/settings.yaml is the one place in this repo that describes something it
// does not drive, because github_organization_settings is all or nothing and
// needs a billing email this repo should not hold. So instead of applying it,
// read it back and say so when it moves. See var.manage_org_settings.

try {
  const live = await api(`/orgs/${ORG}`);
  const want = {
    default_repository_permission: org.default_repository_permission,
    members_can_create_repositories: org.members_can_create_repositories,
    two_factor_requirement_enabled: org.two_factor_requirement_enabled,
    web_commit_signoff_required: org.web_commit_signoff_required,
  };
  let moved = 0;
  for (const [k, v] of Object.entries(want)) {
    if (live[k] === undefined) {
      warn(`organisation setting ${k} is not visible to this token, not checked`);
    } else if (live[k] !== v) {
      fail(`organisation setting ${k} is ${JSON.stringify(live[k])} but org/settings.yaml says ${JSON.stringify(v)}`);
      moved++;
    }
  }
  if (live.plan?.name === undefined) {
    warn("the organisation plan is not visible to this token, not checked");
  } else if (live.plan.name !== org.plan) {
    // Worth its own message: two things in this repo exist only because the
    // plan is Free, and both stop being true on a paid plan.
    fail(`the organisation is on the "${live.plan.name}" plan but org/settings.yaml says "${org.plan}". Rulesets on private repositories and organisation-level rulesets both depend on this.`);
    moved++;
  }
  if (!moved) pass("organisation settings match org/settings.yaml");
} catch (e) {
  fail(`could not read the organisation: ${e.message}`);
}

// ------------------------------------------------------ 3. secret names --
//
// Names only. No value enters this repository or its state file.

try {
  const live = (await api(`/orgs/${ORG}/actions/secrets`)).secrets?.map((s) => s.name) ?? [];
  const missing = (secrets.required ?? []).map((s) => s.name).filter((n) => !live.includes(n));
  if (missing.length) {
    fail(`organisation secrets in org/secrets.yaml that do not exist: ${missing.join(", ")}.`);
  } else {
    pass(`every secret in org/secrets.yaml exists (${live.length} set)`);
  }
} catch (e) {
  const msg = `could not list organisation secrets (${e.message}). Needs admin:org, or an App with organisation secrets read.`;
  if (REQUIRE_SECRETS) {
    fail(`${msg} org/secrets.yaml is a gate or it is a comment; without this permission it is a comment.`);
  } else {
    warn(`${msg} Skipping.`);
  }
}

process.exit(rc);
