# `master` protection (proposed, FOX-38)

**Status: proposed, not applied.** The live settings are unchanged. The owner (or Mini, on
the owner's say-so) applies them with the commands below **after** the FOX-38 PR is merged.
Applying them first would block every open PR, because the new checks only exist on
branches that contain the FOX-38 workflows.

## What is live today

`master` has one repository ruleset (id `25890340`, name `master`, active, no bypass):

```json
{
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" }
  ]
}
```

So force-pushes and deleting `master` are already blocked. Direct pushes are **not**:
the 3.1.4 build bump (`cb7d78c`) was pushed straight to `master`. There is no classic
branch protection, and the repository allows squash merges only.

## What the proposal adds

[`master-ruleset.json`](master-ruleset.json) is the whole ruleset, the three rules above
plus these:

| Rule | Setting | Why |
|---|---|---|
| `pull_request` | required, 0 approvals, squash only | Blocks direct pushes, including release bumps, which now go through a PR (see [ci-cd-guardrails.md](ci-cd-guardrails.md#after-the-merge-testflight)). 0 approvals because the account that opens every PR can't approve its own. The `Mini LGTM` status takes the place of an approval. |
| `required_status_checks` | `strict: true` | The branch must be up to date with `master` before merging. Stacked PRs then merge in order, and each one is tested against what is actually on `master`. |
| required: `Unit tests` | CI | Skips itself (green) for docs, media, `fastlane/`, `web/` and `workers/`-only PRs. |
| required: `Vulnerability checks` | CI | Fails only on TruffleHog **verified** secrets. osv-scanner and unverified findings are warnings. |
| required: `PR policy` | PR policy | `feature/` branch, `FOX-nn` in the branch or title, `Depends on #N` merged first, release version/build/What's New consistent. |
| required: `Secret files` | PR policy | No `debug.xcconfig` / `release.xcconfig` / `GoogleService-Info.plist` / `.env` / `.dev.vars` / signing keys, no force-added gitignored files, no real-looking secret values. |
| required: `Workers` | Workers | One summary check on every PR, green when no Worker changed. |
| required: `Mini LGTM` | Mini LGTM | Commit status set from Mini's review. See below. |
| `bypass_actors` | none | Every actor here, Orca and Mini included, uses the owner's admin account. An admin bypass would exempt the agents too, so there is none. |

`integration_id: 15368` is GitHub Actions. It means only a workflow can satisfy a check:
a `gh api …/statuses` call made with a personal token does **not** turn `Mini LGTM` green.

`Claude Code Review` (check name `review`) stays advisory, not required. It depends on an
external token and quota, and its findings go into Mini's LGTM anyway.

## The LGTM approach

GitHub won't let an account approve its own PR, and every PR here is opened from the
owner's account. The options were:

1. **A second approver account** (a bot or machine user with write access) whose
   APPROVE review is required. This is GitHub's native mechanism, but it needs another
   seat and its credentials on the Mini.
2. **A status check gated on Mini's LGTM comment.** This is the chosen approach. It
   matches what Mini already does: a PR review left as a *Comment* whose body starts with
   `**Mini LGTM**`.

[`mini-lgtm.yml`](../.github/workflows/mini-lgtm.yml) runs on every push to the PR and
every review. [`tools/mini_lgtm_gate.py`](../tools/mini_lgtm_gate.py) then sets the
`Mini LGTM` status on the head commit:

- **pending** until a Mini review exists. A Mini review is a non-dismissed review by an
  owner, member or collaborator whose body starts with `Mini`.
- **success** when the latest Mini review starts `Mini LGTM` and either was left on the
  head commit, or was left on an earlier commit with the same net change. The second case
  covers a rebase or "Update branch" with no edits of its own. Checked against the real
  PRs: #30 and #31 were rebased after their LGTM and stay green, while a branch with new
  commits after the LGTM goes back to pending.
- **failure** when the latest Mini review is anything else (`**Mini** changes needed: …`).
- Dismissing the review withdraws the LGTM.

Limits, stated plainly: Orca, Mini and the owner share one GitHub account, so the gate
checks a convention, not an identity. **Orca must never post a review that starts with
"Mini".** The gate scripts run from `master`'s copy, so a PR can't loosen its own gate,
but a PR that edits `.github/` or `tools/` still deserves a careful read from Mini. The
user greenlight is a human step (the PR template's checkbox), not a check.

`FOX-nn` in the branch or title is enforced by the `PR policy` check, not by a ruleset
metadata rule.

## Apply (after the FOX-38 PR is merged)

```sh
# 1. Save the current ruleset, for rollback.
gh api repos/7kfpun/SwiftUI-TWAQI/rulesets/25890340 > /tmp/master-ruleset.before.json

# 2. Replace it with the proposal.
gh api --method PUT repos/7kfpun/SwiftUI-TWAQI/rulesets/25890340 \
  --input docs/master-ruleset.json

# 3. Check it.
gh api repos/7kfpun/SwiftUI-TWAQI/rulesets/25890340 --jq '.rules[].type'
#    deletion, non_fast_forward, required_linear_history, pull_request, required_status_checks
```

Then, on the next PR:

- Push a `feature/fox-nn-…` branch and open a PR. `PR policy`, `Secret files`, `Workers`
  and `Mini LGTM` (pending) should all report.
- Leave a `**Mini LGTM**` review and the status should turn green. If the merge box
  still lists `Mini LGTM` as expected even though the status is green, drop
  `"integration_id": 15368` from the `Mini LGTM` entry and PUT again.
- Any PR opened before this change has to be updated from `master` once so that it picks
  up the new checks.

## Rollback

```sh
# Back to exactly what was live before FOX-38.
gh api --method PUT repos/7kfpun/SwiftUI-TWAQI/rulesets/25890340 --input - <<'JSON'
{
  "name": "master",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" }
  ]
}
JSON
```

For an emergency without a full rollback, set `"enforcement": "disabled"` with the same
PUT and set it back to `"active"` afterwards.
