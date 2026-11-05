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
| `pull_request` | required, 0 approvals, squash only | Blocks direct pushes, including release bumps, which now go through a PR (see [ci-cd-guardrails.md](ci-cd-guardrails.md#after-the-merge-testflight)). 0 approvals because the account that opens every PR can't approve its own. The `LGTM` status takes the place of an approval. It turns green on a review from another agent. |
| `required_status_checks` | `strict: true` | The branch must be up to date with `master` before merging. Stacked PRs then merge in order, and each one is tested against what is actually on `master`. |
| required: `Unit tests` | CI | Reports at every level: green in seconds for docs, media, `android/`, `assets/`, `ios/fastlane/`, `web/`, `workers/` and `.github/`-only PRs (other than `ci.yml`); build only for other app changes; build + subset for guarded paths ([ci-cd-guardrails.md](ci-cd-guardrails.md)). |
| required: `Vulnerability checks` | CI | Fails only on TruffleHog **verified** secrets. osv-scanner and unverified findings are warnings. |
| required: `PR policy` | PR policy | `feature/` branch, `FOX-nn` in the branch or title, `Depends on #N` merged first, release version/build/What's New consistent. |
| required: `Secret files` | PR policy | No `debug.xcconfig` / `release.xcconfig` / `GoogleService-Info.plist` / `.env` / `.dev.vars` / signing keys, no force-added gitignored files, no real-looking secret values. |
| required: `Workers` | Workers | One summary check on every PR, green when no Worker changed. |
| required: `LGTM` | LGTM | Commit status set from another agent's review (see below). |
| `bypass_actors` | none | Every actor here, Orca and Mini included, uses the owner's admin account. An admin bypass would exempt the agents too, so there is none. |

`integration_id: 15368` is GitHub Actions: those five checks can only be satisfied by a
workflow. `LGTM` is a commit *status*, not a check run, and it is left without an
`integration_id` on purpose. It isn't confirmed that a ruleset matches a status posted with
`GITHUB_TOKEN` to the Actions app, and if it doesn't, every PR would be blocked. The
trade-off is that a status posted by hand (`gh api …/statuses` with a personal token) would
also count. Optional hardening once the ruleset is live: add `"integration_id": 15368` to
that entry, then confirm on one PR that a real agent review still unblocks the merge. If it
doesn't, remove the id again.

`Claude Code Review` (check name `review`) stays advisory, not required. It depends on an
external token and quota, and its findings go into the reviewer's verdict anyway.

## The LGTM approach

GitHub won't let an account approve its own PR, and every PR here is opened from the
owner's account. The options were:

1. **A second approver account** (a bot or machine user with write access) whose
   APPROVE review is required. This is GitHub's native mechanism, but it needs another
   seat and its credentials on the Mini.
2. **A status check gated on a reviewer's LGTM.** This is the chosen approach. A pull
   request review or comment counts when its first line is "LGTM", optionally after one
   word naming the reviewer, with nothing after it but punctuation or a `(head <sha>)`
   note (`**Grok LGTM**`, `**Copilot LGTM** (head abc1234)`, `LGTM`). "LGTM?",
   "LGTM, but …", and a negating word in the name slot ("Never LGTM", "Almost LGTM")
   don't count. The gate keeps no list of agents: reviewers come and go, and any name works.
   `**Grok review**` without a verdict doesn't count either.

[`lgtm.yml`](../.github/workflows/lgtm.yml) runs on every push to the PR, every
review, and every PR comment. [`tools/lgtm_gate.py`](../tools/lgtm_gate.py)
then sets the `LGTM` status on the head commit:

- **pending** until an LGTM exists, when a later "changes needed" overrides it, and
  again when the branch changes after it.
- **success** when the latest verdict is an LGTM left on the head commit, or on an earlier
  commit with the same net change. The second case covers a rebase or "Update branch"
  (a merge from `master`) with no edits of its own, so keeping a PR up to date with
  `master` never needs another LGTM. "Same net change" compares the PR's own added and
  removed lines per file against the merge base; blob ids, hunk positions and the
  unchanged context lines around each hunk are ignored, since they move whenever
  `master` edits nearby. Resolving a conflict, or any other edit of the branch's own
  changes, needs a fresh LGTM. A review is tied to its commit. A comment is tied to the
  commit in its `(head <sha>)` note, so it survives a rebase too; without a note it
  covers the head only when it was written at or after that commit.
- Dismissing the review withdraws it. The latest verdict wins: a review or comment whose
  first line is "changes needed" or "changes requested" (optionally after a name, e.g.
  `**Codex — changes needed**`), or a review in GitHub's `CHANGES_REQUESTED` state, sets
  the status back to pending until a newer LGTM. The status means a reviewer approved
  this head.

Limits, stated plainly: Orca, Mini and the owner share one GitHub account, so the gate
checks the review's first line, not a separate login. A bot counts when its first line
is a verdict, except `claude[bot]`: the Claude Code Review workflow is advisory, and its
progress comment appears before it has reviewed anything. A person counts only with
owner, member, or collaborator access. Don't start a comment with "LGTM" unless you
reviewed the head. The gate script runs from
`master`'s copy, so a PR can't loosen its own gate, but a PR that edits `.github/` or
`tools/` still deserves a careful read. The user greenlight is a human step (the PR
template's checkbox), not a check.

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
  and `LGTM` (pending) should all report.
- Leave a review whose first line is `**<Name> LGTM**`. The
  status should turn green and the merge box should stop listing `LGTM` as expected.
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
