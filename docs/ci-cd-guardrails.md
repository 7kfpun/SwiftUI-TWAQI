# CI/CD guardrails (FOX-38)

How a change gets from a ticket to users, and what enforces each step.

```
Linear FOX-nn → Orca codes on feature/fox-nn-… → draft PR → self-review → CI green → ready
  → another agent's review → user greenlight → squash-merge
  → (only if the ticket/PR names it) TestFlight · App Store Connect · Firebase Hosting
```

A merge ships nothing to users except Cloudflare Workers, which deploy on merge when
`workers/` changes (after the owner approves the deploy), and the scheduled push sends,
which run from whatever `master` holds. Every other release step is a separate,
deliberate action, taken only when the ticket or PR names it.

## Checks on a PR to `master`

| Check | Workflow | Runs on | Fails when |
|---|---|---|---|
| `Unit tests` | `ci.yml` | non-draft `feature/*` | the level script's tests or list check fail; the build fails (**build** and **test** levels); or the `-only-testing` subset fails (**test** level, built from the CI-only `TWAQI-CI` scheme, which leaves out the UI-test runner). Green in seconds at the **skip** level. Levels below. |
| `Vulnerability checks` | `ci.yml` | non-draft `feature/*` | TruffleHog **verified** a secret in the PR's commits. Unverified findings, osv-scanner results and tool failures are warnings, posted as a PR comment. |
| `PR policy` | `pr-policy.yml` | every PR, drafts too | the branch isn't `feature/…`; no `FOX-nn` in the branch or title; a `Depends on #N` PR isn't merged; Fastfile `APP_VERSION`, `MARKETING_VERSION`, build numbers or What's New disagree (`tools/check_release_consistency.py`). |
| `Secret files` | `pr-policy.yml` | every PR, drafts too | the net diff adds or changes `debug.xcconfig`, `release.xcconfig`, `GoogleService-Info.plist`, `.env*`, `.dev.vars*`, signing keys or profiles; force-adds a gitignored file; or adds a real-looking secret value (`tools/check_secret_files.py`). Example and placeholder files pass. |
| `Workers` | `workers.yml` | non-draft PRs | a changed Worker fails its typecheck or `wrangler deploy --dry-run`. Green when no Worker changed. |
| `Services` | `services.yml` | non-draft PRs | `services/twaqi-api` fails `cargo fmt --check`, clippy (`-D warnings`) or `cargo test --locked` (golden fixtures included). Green when `services/` didn't change. Deploys nothing. |
| `Public text` | `public-text.yml` | non-draft PRs, again on each description edit | the title, description, a commit message or an added line names a non-website host, an IP or network range, a private email, or network-exposure details (`tools/public_text_check.py`). Hosts are fine in files that need them to work (config, scripts, app constants, tests). See [Public repo](#public-repo-what-stays-out). |
| `LGTM` (status) | `lgtm.yml` | every push, review, and PR comment | pending until a reviewer's LGTM covers the head: a review or comment whose first line is `**<Name> LGTM**` (any name, or none). A rebase or update from `master` with no change of its own keeps the LGTM. A later "changes needed" sets it back to pending; the advisory `claude[bot]` doesn't count. |
| `review` | `claude-code-review.yml` | non-draft `feature/*` | advisory Claude review, not required. |

`Unit tests` levels (FOX-79). The job's first steps check out the repo, run
`tools/test_ci_test_level.py` and `tools/ci_test_level.py check`, then decide a level from
the PR's file list (`gh api …/pulls/N/files`). The highest level any file needs wins:

| Level | PR touches only… | Runs |
|---|---|---|
| **skip** | `workers/`, `services/`, `web/`, `fastlane/`, `assets/`, docs (`.md`), media, `.github/**` except `.github/workflows/ci.yml` and `.github/actions/unit-tests-build/` | nothing more; the check is green |
| **build** | any other path (Swift, strings, asset catalogs, widget / watch / visionOS, `project.pbxproj`) | config, caches, `pod install`, `build-for-testing`; no simulator pick (it starts CoreSimulatorService), boot or test run |
| **test** | a `CI_GUARDED_PATHS` entry, `.github/workflows/ci.yml`, `.github/actions/unit-tests-build/`, `tools/ci_test_level.py` or its test, `Podfile`, `Podfile.lock`, `Package.resolved` | everything below: build, boot, the subset |

- `CI_GUARDED_PATHS` (job `env` in `ci.yml`) sits beside `CI_TEST_SUITES`, the subset: the
  suites' test files and the source files they test, read off each suite. `check` fails the
  job when a suite's file isn't listed or an entry matches no file (a rename).
- The PR label **`ci-full-tests`** forces **test**. Labels are fetched when the job runs, so
  add the label and re-run the job (or push). Adding a label alone starts no run.
- An empty file list, or a failed files or labels API call, gives **test**: never skip on doubt.
- The step prints the level and the files that decided it, and writes them to the job summary.
- The check is `Unit tests` at every level, so `master`'s required checks and the `PR policy`
  and `LGTM` gates are unaffected. The full `TWAQITests` still runs locally before a PR is
  marked ready; CI's simulator run is the second check.

`Unit tests` speed-ups (FOX-64): the simulator is picked in the background during the
build and booted after it, in sequence: booting during the build slowed both down on slow
runners. The build targets a generic simulator (`ARCHS=arm64`) and the tests run with
`test-without-building` against the booted simulator's udid. Swift packages, `Pods/` and the
DerivedData build products are cached. The DerivedData key is exact
(Xcode build + `Podfile.lock` + `Podfile` + `Package.resolved`, no restore-keys), so
products built against other dependencies are never restored, and app and test sources
always rebuild (checkout gives them new mtimes). A miss just downloads and builds as before.

Shared caches (FOX-65). A PR can read its own caches and `master`'s, never another PR's,
and CI runs only on `pull_request`, so caches used to be saved per PR: every PR's first run
was cold, and each PR kept its own ~880 MB copy of the same keys (over the 10 GB repo
limit with a handful of open PRs, so caches were also evicted). Now:

- The job's cache and build steps are one composite action,
  `.github/actions/unit-tests-build`, used by `ci.yml` and by the **`CI cache`** workflow
  (`ci-cache.yml`). Keys and build flags live only there, so the two can't drift apart.
  The `Prepare gitignored config` step stays in each workflow file (its placeholder Firebase
  host is allowed by `Public text` only in `.github/workflows/*.yml`); `ci_test_level.py
  check` fails the `Unit tests` job when `ci-cache.yml`'s copy differs from `ci.yml`'s.
- `CI cache` runs on `master` only: on a push that changes `Podfile`, `Podfile.lock`,
  `Package.resolved`, the `TWAQI-CI` scheme, `ci.yml`, `ci-cache.yml` or the action; weekly
  (Monday 03:17 UTC: caches unused for 7 days are evicted, and a runner image with a new
  Xcode build changes the DerivedData key); and by `workflow_dispatch`. It builds with
  `build-for-testing` exactly as the PR job does, with no simulator or tests, and saves the
  three caches. When all three keys already exist it only restores them (a restore counts
  as a use) and stops. `contents: read`, no secrets; the config placeholders are the same.
- Caches are restored with `actions/cache/restore` and saved with `actions/cache/save` right
  after a successful build, each only when its exact key missed. A PR whose dependencies
  match `master` restores `master`'s caches and saves nothing. A PR that changes them saves
  its new keys in its own scope, so its later runs are warm.
- The build prints `-showBuildTimingSummary`, so a cold build's log shows where the time
  went.

"CI green" for undrafting means everything except `LGTM`, which stays pending until
a reviewer's LGTM covers the head.

Undraft race: `ci.yml` and `claude-code-review.yml` cancel superseded runs per PR, and
their concurrency key includes whether the PR is a draft. A push and "Ready for review"
in the same second used to let the push's run, whose payload still said draft and so
skipped everything, cancel the ready-for-review run, which left CI skipped. With
draftness in the key, a draft run can only cancel draft runs, so undrafting always gets
a full run. `Workers` has no per-PR cancel. `PR policy` and `LGTM` don't depend on
draftness, and their newest run reads the PR's current state.

Stacked PRs: `PR policy` only re-runs on the PR's own events, so it stays red after the
base PR merges until the stacked PR is updated. Once protection requires up-to-date
branches, that update has to happen anyway. Until then, re-run the check by hand. Which checks block a merge is set by `master`'s ruleset:
[master-protection.md](master-protection.md) (proposed, not applied yet).

The secret checks are layered. `Secret files` fails on what the PR would merge, whether
or not the key works. `Vulnerability checks` fails on credentials TruffleHog proved live,
anywhere in the PR's commits. The repository is public, so anything pushed is already
exposed: rotate the key, then rewrite the branch.

## Public repo: what stays out

`Secret files` and `Vulnerability checks` catch keys and secret files. `Public text`
catches the patterns below in a PR's title, description, commit messages and added lines,
but not in comments, reviews, or a description edited back later, and wording slips past
patterns. Commit messages, PR titles and descriptions, review and issue comments, and docs
are all public, and so is a description's **edit history** (the "edited" menu shows every
earlier version).

Keep out of all of them:

- IP addresses, network ranges, allow-lists, and changes to network access rules.
- Security posture: which services are or were reachable from anywhere, what was locked
  down and when, how a service is reached past its access controls.
- Incident details: attacker or scanner IPs, outage causes, what was hit or exposed.
- Secret values or any part of them (tokens, passwords, keys, DSNs), database hosts, and
  account emails.
- **Hostnames, except the public websites.** `taiwanair.wahthefox.com`, `kf-twaqi.web.app`
  and `kf-nihongo.web.app` are fine. Every other host (the API and webcam host, Directus,
  `workers.dev` URLs, Cloud Run URLs, the Lambda's API Gateway) is named by its role: "the
  webcam host", "Directus", "the Worker's workers.dev URL", "Cloud Run". The real value
  stays in the code or config that needs it to work (`wrangler.jsonc`, xcconfig, a
  script's request URL), and in docs as a placeholder (`<webcam host>`) or a command that
  looks it up (`gcloud run services describe … --format 'value(status.url)'`).

Fine to write: resource **names** a runbook or the code needs (a Secret Manager secret's
name, a Cloud Run service, a Worker route), commands with placeholders, and test or
benchmark results.

Where the rest goes: the Linear ticket. Linear is internal, so hosts, infra state and
incident notes are fine there. The PR body says "infra changes: see FOX-nn" and links it.

If something slipped into a PR description: edit it out, then delete the older versions
from the description's edit history ("edited" menu → the revision → **Delete revision
from history**; needs write access and a logged-in browser, not possible through the
API). The same works for comments. In a commit message or a file: rewrite the branch
before merge; after merge, treat it as public.

## Security

**Scan before a PR goes ready, and after any secret scare**, over all history and every
branch (both tools: `brew install gitleaks trufflehog`):

```sh
gitleaks git --log-opts="--all" --redact .
trufflehog git file://. --results=verified,unknown,unverified
```

CI runs TruffleHog on each PR's commits (`Vulnerability checks`); the full-history scan is
by hand. Report findings in Linear, not on the PR.

**Rotate first.** A credential that reached GitHub, a shipped app binary or a log is
exposed for good: revoke or rotate it at its source (Directus, OneSignal, Google Cloud,
Cloudflare, Firebase, OpenRouter), then remove it from the code. Rewriting history is only
worth it when a real secret got in, and even then GitHub keeps old PR commits until
GitHub Support purges them; it never replaces rotation.

**Anything in the app is public.** Values in `xcconfig` end up in the shipped binary, and
old builds stay installed for years. So a token the app carries must be read-only or
create-only, limited to the collections it needs, and revocable without breaking current
builds. Writes go through a Worker that checks the caller (as the push API does), not
through a shared token.

**Servers and databases** reach each other through their platform's private connections
(Cloud Run's Cloud SQL connection, Worker secrets), not through open network rules.
Changes to who can reach what are recorded in Linear, never in the repo.

## Deploy paths, each separate from merging

| What | How | Gate |
|---|---|---|
| **Squash-merge** | GitHub merge button / `gh pr merge --squash`, after the user's greenlight | ruleset: required checks + `LGTM` (another agent's review); PR template checkboxes |
| **Cloudflare Workers** | `workers.yml` on push to `master` (changed Workers only); `workflow_dispatch` to redeploy | the PR's `Workers` check; deploy runs from `master` only |
| **Cloud Run `twaqi-api`** (read API origin, FOX-82) | by hand, `gcloud run deploy` from `services/twaqi-api` ([runbook](../services/twaqi-api/README.md#deploy-by-hand)) | the owner, from master; merging never deploys it |
| **Push sends** (scheduled AQI alerts) | `push-sender.yml`: `schedule` `20 */2 * * *` and `workflow_dispatch` (dry run on by default), running `workers/twaqi-push-sender`'s `run()` under Node | `push-sender` environment (master only, **no reviewers**, so the schedule can run); the workflow also refuses other branches before the environment is used. See below. |
| **Firebase Hosting** | `firebase-hosting.yml`, `workflow_dispatch` only, from `master`: `check-domain` · `deploy-main` | `firebase-hosting` environment (owner approval) |
| **DNS cutover** | by hand, Cloudflare zone `wahthefox.com` + Firebase console custom domain | [web-hosting.md](web-hosting.md) steps 3-5; verify with the `check-domain` action |
| **TestFlight** | `fastlane release_build` on the Mac mini (cloud-managed signing needs the Xcode Apple ID, so it can't run on GitHub's runners) | named in the ticket/PR; the lane runs `check_release_consistency.py` first |
| **App Store Connect** metadata / screenshots / review | `fastlane upload_metadata`, `upload_*screenshots`; submission by hand | named in the ticket/PR; screenshot lanes refuse to run unless the version is editable |

### Firebase Hosting environment

**Created on 2026-11-01 (FOX-38):** `firebase-hosting`, with required reviewer `7kfpun`
(self-review allowed, since every run is triggered from that account) and deployment
branches limited to `master`. **No secret yet.** The workflow fails at "Write service
account key" until the owner adds `FIREBASE_SERVICE_ACCOUNT` as an *environment* secret,
so only approved runs can read it:

```sh
# Service account for project kf-twaqi with the Firebase Hosting Admin role.
gh secret set FIREBASE_SERVICE_ACCOUNT --env firebase-hosting < kf-twaqi-hosting-sa.json
```

The environment was created with the commands below. They are kept for re-creating it.
Create the environment before adding any secret: a workflow that names a missing
environment creates it with no protection.

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
```

`2672802` is the `7kfpun` user id. Until the secret is added, deploy the site from a
laptop as in [web-hosting.md](web-hosting.md). The same order applies there.

### Push sender environment (FOX-71)

The AQI alert sends moved from the `twaqi-push-sender` Worker's cron to GitHub Actions:
the Cloudflare account is on the Workers Free plan, whose 50 subrequests per run can't
carry them, and which rejects the `limits` block they needed. The Worker keeps the app's
`/app/v1` API, the manual `/run` / `/test` routes, and `POST /internal/events`, which
writes the GitHub run's per-send events to Analytics Engine (`twaqi_push_events`, same data
points as before). It still deploys through `workers.yml` (`workers-production`).

`push-sender.yml` runs in its own environment, `push-sender`: deployment branches
limited to `master`, **no required reviewers** (`workers-production` makes every job wait
for an approval, which a schedule can't). Its secrets, copies of the Worker's:
`FCM_SERVICE_ACCOUNT`, `DIRECTUS_PUSH_TOKEN`, `AQI_API_BASE`, and `SYNC_TOKEN` (for the
event forward to the Worker, whose URL is `PUSH_SENDER_URL` in the workflow). Create the environment before
the workflow's first run, since a workflow that names a missing environment creates it
unprotected. Commands: [`workers/twaqi-push-sender/README.md`](../workers/twaqi-push-sender/README.md#the-push-sender-environment-github-actions).

- One run at a time (`concurrency: push-sender`), `timeout-minutes: 30` (40k sends take
  about 3 minutes). The job fails when the run throws or any alert failed to send (dead
  tokens and sends deferred to the next run don't count). Events that couldn't be
  forwarded (one retry per 250) are a warning, never a re-send or a failure. The log shows
  counts only.
- GitHub's schedule is best effort: runs can start late or be skipped, and scheduled
  workflows switch off after 60 days without repository activity (re-enable under Actions).
  A late run loses nothing: unsent crossings go out on the next run, never twice.
- Back on Workers Paid: restore the cron, `limits` and the scheduled handler in the Worker,
  and delete `push-sender.yml` in the same PR.

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
# PR → CI + another agent's review → squash-merge
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
