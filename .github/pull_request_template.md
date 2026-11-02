## Ticket

FOX-nn — https://linear.app/foxtechnologies/issue/FOX-nn

> Quote the ticket's scope / acceptance criteria here. The Claude review checks the diff against it.

<!-- Stacked PR? Keep a line like the one below: the PR policy check stays red until #N is merged
     (then update this branch from master, or re-run the check).
Depends on #N
-->

## What changed

-

## Verification

<!-- Claim only what the diff and these runs show. -->

- [ ] Full `TWAQITests` passed locally (Mac mini / Orca), or N/A: no app code changed
- [ ] `cd workers/twaqi-workers && npm test`, or N/A: `workers/` unchanged
- [ ] Self-review against the CLAUDE.md checklist (scope, body claims, push / favourites ↔ alerts invariants)

## Merge gates

Don't merge until every box is ticked. Merge is a **squash-merge** done after the greenlight. Details: `docs/ci-cd-guardrails.md`.

- [ ] CI green: Unit tests, Vulnerability checks, PR policy, Secret files, Workers
- [ ] **LGTM**: another agent's LGTM that covers the current head: a pull request review or comment whose first line is `**<Name> LGTM**`. The `LGTM` status turns green.
- [ ] **User greenlight**: the user said to merge this PR (quote or link it)
- [ ] **Merge order**: not stacked / stacked on #N, which is merged (the `Depends on #N` line above)

## Release actions

Only what the ticket or this PR names. Nothing ships from a merge except Workers (they deploy when `workers/` changes).

- [ ] None
- [ ] TestFlight upload (`fastlane release_build`, after the merge). Named in:
- [ ] App Store Connect: metadata / screenshots / review submission. Named in: <!-- run `fastlane asc_version_state` first; screenshots can't change while WAITING_FOR_REVIEW -->
- [ ] Firebase Hosting deploy / DNS cutover (`Firebase Hosting` workflow, `docs/web-hosting.md`). Named in:
