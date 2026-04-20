# Contributing to ARTEMIS

```
┌─ Quick start ────────────────────────────────────────────────────────────────┐
│                                                                              │
│  # Install ARTEMIS                                                           │
│  devtools::install_github("OHDSI/ARTEMIS")                                  │
│                                                                              │
│  # Activate local commit message guard (recommended):                       │
│  git config core.hooksPath .githooks                                        │
│                                                                              │
│  # Install commitizen (needed for cz commit wizard + cz bump):              │
│  pip install commitizen                                                      │
│                                                                              │
│  # Commit format enforced on every PR by CI:                                │
│  type(scope): short description                                              │
│  e.g.  fix(r-bridge): guard against empty alignment output                  │
│        feat(scoring): pass gap-open param to alignment                      │
│                                                                              │
│  # If CI blocks your PR → Actions tab → lint-commits job → fix              │
│  # the offending commit(s) with git rebase -i, then force-push.             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Getting started

ARTEMIS is an R package. No git clone is required — `devtools` handles the
download:

```r
devtools::install_github("OHDSI/ARTEMIS")
```

If you are contributing code, fork the repository on GitHub and clone your fork.
Work on a branch cut from `develop`, then open a PR targeting `develop`.

---

## Branch naming

All branches must follow the canonical pattern:

```
<type>/<scope-or-ticket>/<short-description>

e.g.  feat/GH-42/cython-param-pass
      fix/GH-67/empty-alignment
      chore/GH-xx/update-deps
      ci/GH-xx/r-tests
      release/1.5.0
      hotfix/1.4.2
```

Valid types: `feat fix chore docs style refactor test ci release hotfix`

See `vignette("branch-versioning")` for the full Gitflow topology and merge
direction.

---

## Commit format

ARTEMIS uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description
```

Examples:

```
feat(cython): pass gap-open/extend params to C extension
fix(r-bridge): guard against empty alignment output
ci(docker): add arm64 image build workflow
chore(data): update regimen reference data 2025
perf(scoring): remove redundant max in TSW score matrix
```

See `vignette("testing-strategy")` — *Conventional Commits* section for the
full type list, scope vocabulary, and breaking-change syntax.

---

## Local commit validation

The `.githooks/commit-msg` hook gives immediate local feedback before a bad
commit reaches CI.

**Activation (one command):**

```bash
git config core.hooksPath .githooks
```

**What changes after activation:**

```bash
git commit -m "fix stuff"
# ✘ Invalid commit message.
#   Expected: type(scope): description
#   Got:      fix stuff
#   See: vignette("testing-strategy") — Conventional Commits section
# → commit aborted

git commit -m "fix(r-bridge): guard against empty alignment output"
# ✔ commit proceeds normally
```

Hooks are **optional locally** — CI is the mandatory gate. No Python, no Node,
no extra installs required for the hook itself.

---

## CI validation

Every PR triggers `.github/workflows/lint.yml`, which runs three jobs:

| Job | What it checks |
|-----|---------------|
| `lint-commits` | Every commit in the PR via `cz check` |
| `lint-branch` | Branch name against the naming regex |
| `r-tests` | `devtools::test()` + R CMD check |

**If CI blocks your PR:**

1. Go to the **Actions** tab on GitHub.
2. Open the failing job (`lint-commits` or `lint-branch`).
3. Read the `✘` line — it shows the exact offending commit or branch name.
4. Fix commits with `git rebase -i`, then force-push:

```bash
git rebase -i origin/develop
# change "pick" to "reword" on bad commits, fix the messages
git push --force-with-lease
```

---

## PR checklist

Before opening a PR, confirm:

- [ ] All commits follow the Conventional Commits format
- [ ] Branch name follows `type/scope/description`
- [ ] Tests pass locally: `devtools::test()`
- [ ] R CMD check passes: `devtools::check()`
- [ ] `DESCRIPTION` version has **not** been manually bumped (release manager
      runs `cz bump` — contributors do not touch the version field)
- [ ] `NEWS.md` has an entry for user-visible changes

---

## Cutting a release

Only the release manager needs this. Everyone else: stop here.

```bash
pip install commitizen   # one-time setup

# On release/* branch:
cz bump          # auto-bumps DESCRIPTION Version, updates CHANGELOG.md,
                 # creates a signed git tag (e.g. v1.5.0)

git push && git push --tags
```

`cz bump` reads commits since the last tag and determines the next version
automatically (semver). See `vignette("testing-strategy")` — *Release workflow*
section for details.

---

## Python / Cython internals

Python and Cython are an **implementation detail** of ARTEMIS. Contributors do
not need to install Python, touch `.py` / `.pyx` files, or understand the bridge
layer. The R test suite (`test-100-bridge.R`) exercises the full stack
automatically.

---

## Technical Debt Standard

### When to open a tech-debt issue

Open one when you encounter any of the following:

- Hard-to-maintain code with unclear intent
- A temporary workaround that was never revisited
- Poor separation of concerns making future changes risky
- Legacy behaviour whose contract is undocumented
- Missing tests for logic that is correctness-critical

### Required labels

Every tech-debt issue **must** have exactly three labels:

| Group | Pick one |
|-------|----------|
| `type:tech-debt` | always |
| `area:*` | see table below |
| `priority:*` | P1 / P2 / P3 |

**Area labels:**

| Label | Scope |
|-------|-------|
| `area:data-records` | Patient records, regimen reference data |
| `area:scoring` | Aligner algorithm, penalty params, TSW / Cython implementation |
| `area:reports` | Output reports, stats, `writeOutputs` |
| `area:prealign` | Pre-alignment — blacklisting (`cleanByBlacklist`, `buildBlacklistRegex`), `stringDF_from_cdm`, `encode`/`decode` |
| `area:postalign` | Post-alignment — `processAlignments`, `lineOfTreatment`, `removeOverlaps`, `createDrugDF` |
| `area:r-bridge` | R ↔ Python/Cython bridge and reticulate layer |
| `area:ci` | GitHub Actions workflows, hooks, CI tooling |
| `area:docs` | README, man pages, vignettes, CONTRIBUTING |

**Priority rules:**

| Label | When to use |
|-------|-------------|
| `priority:P1` | Blocks development or risks correctness — fix before next release |
| `priority:P2` | Affects maintainability — schedule within current cycle |
| `priority:P3` | Cleanup / low risk — backlog |

### Issue template

Use the **Technical Debt** issue template (`.github/ISSUE_TEMPLATE/tech-debt.yml`).
Required fields:

```
Location    – file + function / line range
Problem     – what is wrong and why
Impact      – risk | maintainability | correctness | performance
Direction   – suggested fix (optional but encouraged)
Related     – linked issues / PRs
```

**Compliant example title:** `debt: cleanText does not handle NULL drug_concept_id`

### Review cadence

- **Who assigns priority:** any maintainer may triage; final priority set by lead maintainer.
- **When reviewed:** at the start of each release cycle when the release branch is cut.
- **How scheduled:** P1 items block the release; P2 items are slotted into the milestone; P3 items go to the backlog.

### Applying labels to GitHub

Label definitions live in `.github/labels.yml`. Apply them once:

```bash
gh label import .github/labels.yml
```
