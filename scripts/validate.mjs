#!/usr/bin/env node
//
// validate.mjs - check the catalogue before OpenTofu ever sees it.
//
// Three kinds of check, in order, stopping at the first kind that fails so the
// output stays readable:
//
//   1. Shape.      Each file against its JSON Schema.
//   2. References. Every team, repository and person named somewhere exists.
//   3. Policy.     The rules a schema cannot express, each with its reason.
//
// Usage:
//   node scripts/validate.mjs              # all of it, including the gate
//   node scripts/validate.mjs --offline    # skips anything needing the network
//   node scripts/validate.mjs --gate-only  # only the whitepaper gate

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { parse as parseYaml } from "yaml";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OFFLINE = process.argv.includes("--offline");
const GATE_ONLY = process.argv.includes("--gate-only");
const MANIFEST_URL = "https://docs.nanocollective.org/whitepapers.json";

// The statuses from StatusBadge.tsx in the docs repo. Kept here as a literal
// rather than fetched, because a typo in the docs should not silently widen
// what this accepts.
const WHITEPAPER_STATUSES = [
  "Draft", "In public review", "Build approved", "Building",
  "Shipped", "Paused", "Declined", "Superseded",
];
const APPROVED = "build approved";

const problems = [];
const warnings = [];
const fail = (file, msg) => problems.push({ file, msg });
const warn = (file, msg) => warnings.push({ file, msg });

const readYamlDir = (dir) => {
  const path = join(ROOT, dir);
  if (!existsSync(path)) return [];
  return readdirSync(path)
    .filter((f) => f.endsWith(".yaml"))
    .sort()
    .map((f) => {
      const rel = `${dir}/${f}`;
      try {
        return { rel, name: basename(f, ".yaml"), doc: parseYaml(readFileSync(join(path, f), "utf8")) };
      } catch (e) {
        fail(rel, `not valid YAML: ${e.message}`);
        return null;
      }
    })
    .filter(Boolean);
};

const repos = readYamlDir("repos");
const teams = readYamlDir("teams");
const people = readYamlDir("people");
const org = parseYaml(readFileSync(join(ROOT, "org/settings.yaml"), "utf8"));
const labels = parseYaml(readFileSync(join(ROOT, "org/labels.yaml"), "utf8"));
const secrets = parseYaml(readFileSync(join(ROOT, "org/secrets.yaml"), "utf8"));

if (problems.length) report();

// report() always exits, so a --gate-only run ends here. Only the file reads
// above are needed to know which whitepapers to ask about.
if (GATE_ONLY) {
  await whitepaperGate();
  report();
}

// ------------------------------------------------------------- 1. shape --

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const schema = (n) => JSON.parse(readFileSync(join(ROOT, "schema", `${n}.schema.json`), "utf8"));
const validators = {
  repo: ajv.compile(schema("repo")),
  team: ajv.compile(schema("team")),
  person: ajv.compile(schema("person")),
};

const checkShape = (items, kind) => {
  for (const { rel, doc } of items) {
    if (validators[kind](doc)) continue;
    for (const e of validators[kind].errors) {
      const where = e.instancePath || "(root)";
      fail(rel, `${where} ${e.message}`);
    }
  }
};
checkShape(repos, "repo");
checkShape(teams, "team");
checkShape(people, "person");

if (problems.length) report();

// -------------------------------------------------------- 2. references --

const repoNames = new Set(repos.map((r) => r.doc.name));
const teamSlugs = new Set(teams.map((t) => t.doc.slug));

for (const { rel, name, doc } of repos) {
  const expected = doc.name === ".github" ? "dot-github" : doc.name;
  if (name !== expected) fail(rel, `filename says "${name}" but name: says "${doc.name}"`);
}

for (const { rel, name, doc } of teams) {
  if (name !== doc.slug) fail(rel, `filename says "${name}" but slug: says "${doc.slug}"`);
  if (doc.parent && !teamSlugs.has(doc.parent)) fail(rel, `parent team "${doc.parent}" has no file in teams/`);
  for (const repo of Object.keys(doc.repositories ?? {})) {
    if (!repoNames.has(repo)) fail(rel, `grants access to "${repo}", which has no file in repos/`);
  }
}

for (const { rel, name, doc } of people) {
  if (name !== doc.github) fail(rel, `filename says "${name}" but github: says "${doc.github}"`);
  for (const t of doc.teams ?? []) {
    if (!teamSlugs.has(t.team)) fail(rel, `member of "${t.team}", which has no file in teams/`);
  }
}

for (const repo of Object.keys(labels.extra ?? {})) {
  if (!repoNames.has(repo)) fail("org/labels.yaml", `extra labels for "${repo}", which has no file in repos/`);
}

// ------------------------------------------------------------ 3. policy --

// The rules the schema cannot word well: ajv reports which keyword failed
// rather than what to do about it.

for (const { rel, doc } of repos) {
  if (!doc.whitepaper && !doc.whitepaper_exempt) {
    fail(rel, "has no whitepaper and no whitepaper_exempt. A repository needs an approved whitepaper, or a stated reason why not: infrastructure, fast-path or predates-pipeline.");
  }

  // The Free plan refuses rulesets on a private repository: the API answers
  // 403 "Upgrade to GitHub Pro". Writing one here would fail at apply time,
  // halfway through, which is a worse place to find out.
  if (doc.visibility === "private" && Object.keys(doc.rulesets ?? {}).length) {
    fail(rel, "is private and carries a ruleset. The Free plan has no rulesets on private repositories. Make it public, or drop the ruleset and say so.");
  }

  // An archived repository is read only. OpenTofu would try the write anyway
  // and fail.
  if (doc.archived && Object.keys(doc.rulesets ?? {}).length) {
    fail(rel, "is archived and carries a ruleset. An archived repository cannot be written to.");
  }
  if (doc.archived && doc.manage_labels) {
    fail(rel, "is archived with manage_labels on. An archived repository cannot be written to.");
  }
}

for (const { rel, doc } of teams) {
  if (doc.privacy === "secret" && Object.keys(doc.repositories ?? {}).length) {
    fail(rel, "is secret and grants repository access. A secret team cannot be a code owner, so Review gates would pass vacuously on those repositories.");
  }
  if (doc.privacy === "secret" && doc.parent) {
    fail(rel, "is secret and has a parent. GitHub does not allow that.");
  }
}

// The module enforces the bypass list. All this checks is that a ruleset is
// deleted rather than left in a file at enforcement: disabled.
for (const { rel, doc } of repos) {
  for (const [key, rs] of Object.entries(doc.rulesets ?? {})) {
    if (rs.enforcement === "disabled") {
      warn(rel, `ruleset "${key}" is disabled. Delete it instead, so the catalogue says what is true.`);
    }
  }
}

// A public repository with no description is not malformed, so it is a warning
// rather than a schema error.
for (const { rel, doc } of repos) {
  if (doc.visibility === "public" && !doc.description) {
    warn(rel, "is public with no description");
  }
  if (doc.visibility === "public" && doc.description && doc.description.length < 10) {
    warn(rel, "has a description too short to tell anyone anything");
  }
}

// A repository with Review gates but no Quality gates can merge failing tests
// behind one approval. A repository with Quality gates and no Review gates can
// merge unreviewed. Neither is wrong, but both should be deliberate.
for (const { rel, doc } of repos) {
  const has = (k) => Boolean(doc.rulesets?.[k]);
  if (has("review") && !has("quality")) warn(rel, "has Review gates but not Quality gates, so a passing suite is not required to merge");
  if (has("quality") && !has("review")) warn(rel, "has Quality gates but not Review gates, so nothing requires a code owner to look");
}

// An owner can change anything, including this repository's own rulesets.
const owners = people.filter((p) => p.doc.org_role === "owner");
for (const { rel, doc } of owners) {
  if (!doc.owner_reason) warn(rel, "is an organisation owner with no owner_reason. Owners can change anything, including this repo's own gates.");
}

// Membership of a secret team is reserved for owners.
for (const { rel, doc } of people) {
  for (const t of doc.teams ?? []) {
    const team = teams.find((x) => x.doc.slug === t.team);
    if (team?.doc.privacy === "secret" && doc.org_role !== "owner") {
      warn(rel, `is in the secret team "${t.team}" without being an owner`);
    }
  }
}

for (const { rel, doc } of teams) {
  if (!doc.all_repositories && Object.keys(doc.repositories ?? {}).length === 0) {
    warn(rel, "grants access to no repository. Either give it a job or delete it.");
  }
}

// all_repositories covers every repository in the catalogue, so naming one at
// the same permission says nothing. Naming one at a different permission is
// the point of being allowed to do both.
for (const { rel, doc } of teams) {
  if (!doc.all_repositories) continue;
  for (const [repo, permission] of Object.entries(doc.repositories ?? {})) {
    if (permission === doc.all_repositories) {
      warn(rel, `names "${repo}" at "${permission}", which all_repositories already grants. Remove the line, or hold it at a different permission.`);
    }
  }
  // An archived repository is read only, so GitHub refuses a permission change
  // on it. A blanket grant would reach one without anybody having typed its
  // name, which is a surprise at apply time rather than review time.
  for (const r of repos) {
    if (r.doc.archived) {
      fail(rel, `has all_repositories, which would reach the archived repository "${r.doc.name}". An archived repository cannot be written to. Name the others explicitly, or unarchive it.`);
    }
  }
}

// manage_labels deletes anything not listed, and GitHub refuses a colour it
// cannot parse with a 422 halfway through an apply.
const allLabels = [
  ...(labels.base ?? []).map((l) => ["base", l]),
  ...Object.entries(labels.extra ?? {}).flatMap(([repo, ls]) => (ls ?? []).map((l) => [`extra.${repo}`, l])),
];
for (const [where, l] of allLabels) {
  if (!l?.name) fail("org/labels.yaml", `${where} has a label with no name`);
  if (!/^[0-9a-f]{6}$/.test(String(l?.colour ?? ""))) {
    fail("org/labels.yaml", `${where} label "${l?.name}" has colour "${l?.colour}". Six lowercase hex digits, no leading "#".`);
  }
}
// The module builds each repository's set from base plus that repository's own
// extras, keyed on the lowercased name, so a clash within one of those sets
// means one label silently wins. Two repositories reusing a name is fine.
for (const [repo, extras] of [["base", []], ...Object.entries(labels.extra ?? {})]) {
  const seen = new Map();
  for (const l of [...(labels.base ?? []), ...(extras ?? [])]) {
    const key = String(l?.name ?? "").toLowerCase();
    if (seen.has(key)) {
      fail("org/labels.yaml", `label "${l.name}" is listed twice for ${repo === "base" ? "the base set" : repo} (${seen.get(key)} and again). The module keys on the lowercased name, so one would silently win.`);
    }
    seen.set(key, l.name);
  }
}

// Secret names only, never values. Catch a value pasted in by accident.
for (const s of secrets.required ?? []) {
  if (Object.keys(s).some((k) => /value|secret_value|content/i.test(k))) {
    fail("org/secrets.yaml", `"${s.name}" looks like it carries a value. Names only in this file.`);
  }
}

// -------------------------------------------------- the whitepaper gate --

await whitepaperGate();

report();

async function whitepaperGate() {
  const needsGate = repos.filter((r) => r.doc.whitepaper);
  if (!needsGate.length || OFFLINE) return;

  let manifest;
  try {
    const res = await fetch(MANIFEST_URL, { signal: AbortSignal.timeout(20000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    manifest = await res.json();
  } catch (e) {
    fail("whitepaper gate", `could not read ${MANIFEST_URL}: ${e.message}`);
    return;
  }

  const bySlug = new Map((manifest.whitepapers ?? []).map((w) => [w.slug, w]));
  for (const w of manifest.whitepapers ?? []) {
    if (!WHITEPAPER_STATUSES.some((s) => s.toLowerCase() === String(w.status).trim().toLowerCase())) {
      warn("whitepaper gate", `docs manifest has "${w.slug}" at status "${w.status}", which is not one of the eight`);
    }
  }
  for (const { rel, doc } of needsGate) {
    const w = bySlug.get(doc.whitepaper);
    if (!w) { fail(rel, `whitepaper "${doc.whitepaper}" is not in the docs manifest`); continue; }
    const status = String(w.status).trim().toLowerCase();
    // 'Building' and 'Shipped' are downstream of an approval that happened,
    // so a repository already past approval still passes the gate.
    if (![APPROVED, "building", "shipped"].includes(status)) {
      fail(rel, `whitepaper "${doc.whitepaper}" is at "${w.status}". A repository needs "Build approved" first.`);
    }
  }
}

function report() {
  const n = (x) => `${x.length} ${x.length === 1 ? "problem" : "problems"}`;
  for (const w of warnings) console.log(`warn  ${w.file}: ${w.msg}`);
  if (warnings.length) console.log("");
  if (!problems.length) {
    const gated = repos.filter((r) => r.doc.whitepaper).length;
    console.log(
      GATE_ONLY
        ? `ok    ${gated} ${gated === 1 ? "repository names a whitepaper" : "repositories name a whitepaper"}, all approved`
        : `ok    ${repos.length} repositories, ${teams.length} teams, ${people.length} people${OFFLINE ? " (offline, whitepaper gate skipped)" : ""}`,
    );
    process.exit(0);
  }
  for (const p of problems) console.error(`FAIL  ${p.file}: ${p.msg}`);
  console.error(`\n${n(problems)}.`);
  process.exit(1);
}
