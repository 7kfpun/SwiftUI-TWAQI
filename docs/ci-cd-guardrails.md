# CI/CD guardrails (FOX-38)

How a change gets from a ticket to users, and what enforces each step.

```
Linear FOX-nn → Orca codes on feature/fox-nn-… → draft PR → self-review → CI green → ready
  → Mini LGTM → user greenlight → squash-merge
  → (only if the ticket/PR names it) TestFlight · App Store Connect · Firebase Hosting
```

A merge ships nothing to users except Cloudflare Workers, which deploy on merge when
`workers/` changes. Every other release step is a separate, deliberate action, taken
only when the ticket or PR names it.

## Checks on a PR to `master`

| Check | Workflow | Runs on | Fails when |
|---|---|---|---|
| `Unit tests` | `ci.yml` | non-draft `feature/*` | the `-only-testing` subset fails. Skips itself (green) when only docs, media, `assets/`, `fastlane/`, `web/` or `workers/` changed. |
| `Vulnerability checks` | `ci.yml` | non-draft `feature/*` | TruffleHog **verified** a secret in the PR's commits. Unverified findings, osv-scanner results and tool failures are warnings, posted as a PR comment. |
| `PR policy` | `pr-policy.yml` | every PR, drafts too | the branch isn't `feature/…`; no `FOX-nn` in the branch or title; a `Depends on #N` PR isn't merged; Fastfile `APP_VERSION`, `MARKETING_VERSION`, build numbers or What's New disagree (`tools/check_release_consistency.py`). |
| `Secret files` | `pr-policy.yml` | every PR, drafts too | the net diff adds or changes `debug.xcconfig`, `release.xcconfig`, `GoogleService-Info.plist`, `.env*`, `.dev.vars*`, signing keys or profiles; force-adds a gitignored file; or adds a real-looking secret value (`tools/check_secret_files.py`). Example and placeholder files pass. |
| `Workers` | `workers.yml` | non-draft PRs | a changed Worker fails its typecheck or `wrangler deploy --dry-run`. Green when no Worker changed. |
| `Mini LGTM` (status) | `mini-lgtm.yml` | every push and review | pending until Mini's `**Mini LGTM**` review covers the head; failure if Mini's latest review isn't an LGTM. |
| `review` | `claude-code-review.yml` | non-draft `feature/*` | advisory Claude review, not required. |

"CI green" for undrafting means everything except `Mini LGTM`, which stays pending until
Mini reviews. Which checks block a merge is set by `master`'s ruleset:
[master-protection.md](master-protection.md) (proposed, not applied yet).

The secret checks are layered. `Secret files` fails on what the PR would merge, whether
or not the key works. `Vulnerability checks` fails on credentials TruffleHog proved live,
anywhere in the PR's commits. The repository is public, so anything pushed is already
exposed: rotate the key, then rewrite the branch.

## Deploy paths, each separate from merging

| What | How | Gate |
|---|---|---|
| **Squash-merge** | GitHub merge button / `gh pr merge --squash`, after the user's greenlight | ruleset: required checks + `Mini LGTM`; PR template checkboxes |
| **Cloudflare Workers** | `workers.yml` on push to `master` (changed Workers only); `workflow_dispatch` to redeploy | the PR's `Workers` check; deploy runs from `master` only |
| **Firebase Hosting** | `firebase-hosting.yml`, `workflow_dispatch` only, from `master`: `check-domain` · `deploy-main` · `deploy-legacy` | `firebase-hosting` environment (owner approval); `deploy-legacy` refuses until `check-domain` passes |
| **DNS cutover** | by hand, Cloudflare zone `wahthefox.com` + Firebase console custom domain | [web-hosting.md](web-hosting.md) steps 3-5; verify with the `check-domain` action |
| **TestFlight** | `fastlane release_build` on the Mac mini (cloud-managed signing needs the Xcode Apple ID, so it can't run on GitHub's runners) | named in the ticket/PR; the lane runs `check_release_consistency.py` first |
| **App Store Connect** metadata / screenshots / review | `fastlane upload_metadata`, `upload_*screenshots`; submission by hand | named in the ticket/PR; screenshot lanes refuse to run unless the version is editable |

### Firebase Hosting environment (one-time, owner)

The workflow is inert until the environment and its secret exist. Create the
environment **before** adding the secret: a workflow that names a missing environment
creates it with no protection.

```sh
# Owner approval, deployable from master only.
gh api --method PUT repos/7kfpun/SwiftUI-TWAQI/environments/firebase-hosting --input - <<'JSON'
{
  "reviewers": [{ "type": "User", "id": 2672802 }],
  "prevent_self_review": false,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
gh api --method POST repos/7kfpun/SwiftUI-TWAQI/environments/firebase-hosting/deployment-branch-policies \
  -f name=master -f type=branch

# Service account for project kf-twaqi with the Firebase Hosting Admin role, stored as an
# environment secret so only approved runs can read it.
gh secret set FIREBASE_SERVICE_ACCOUNT --env firebase-hosting < kf-twaqi-hosting-sa.json
```

`2672802` is the `7kfpun` user id. Until this is done, deploy the site from a laptop as
in [web-hosting.md](web-hosting.md). The same order applies there.

## After the merge: TestFlight

Only when the ticket or PR names a TestFlight build. Direct pushes to `master` are blocked
under the proposed ruleset, so the version/build bump lands through its own small PR:

```sh
git fetch origin && git switch -c feature/fox-nn-release-3.1.5 origin/master
# New version only: bump MARKETING_VERSION in every non-visionOS config and APP_VERSION
# in fastlane/Fastfile, and update fastlane/metadata/{en-US,zh-Hant}/release_notes.txt.
python3 tools/check_release_consistency.py   # also run by release_build and PR policy
fastlane release_build                       # checks again, bumps the build number, archives, uploads
# release_build rewrites TWAQIVision's build number too; put the visionOS configs back.
git commit -am "FOX-nn: Bump 3.1.5 (147) for TestFlight"
# PR → CI + Mini LGTM → squash-merge
```

`check_release_consistency.py` fails when the Fastfile's `APP_VERSION` and a shipped
target's `MARKETING_VERSION` differ, when the app, widget, watch app, watch widget and
notification extension don't share one build number, or when either locale's
`release_notes.txt` is missing, empty or over 4000 characters. visionOS is reported, not
checked: it keeps its own build numbers.

## App Store Connect screenshots

App Store Connect rejects screenshot changes on a version that is `WAITING_FOR_REVIEW`
(or in review, or released), and deliver/Spaceship then retry forever. Every upload
lane (`upload_screenshots`, `upload_watch_screenshots`, `upload_duo_screenshots`,
`upload_vision_screenshots`, and `screenshots`, which calls `upload_screenshots`) now checks
the version's state first. It fails straight away, before staging anything, unless the
state is `PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED` or
`INVALID_BINARY`. There is no override: pulling a version from review is the user's call.

```sh
fastlane asc_version_state   # read-only: "IOS 3.1.4: PREPARE_FOR_SUBMISSION — screenshots editable"
```
