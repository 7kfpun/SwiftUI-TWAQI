# Website hosting: taiwanair.wahthefox.com

The product site, privacy policy and terms (`web/`) move from `kf-twaqi.web.app` to
**https://taiwanair.wahthefox.com**, the same `wahthefox.com` pattern as
`japanesedaily.wahthefox.com`. (FOX-26)

## Layout

| Firebase Hosting site (project `kf-twaqi`) | Target | Config | Serves |
|---|---|---|---|
| `taiwanair-wahthefox` (new) | `main` | `firebase.json` | `web/`, with custom domain `taiwanair.wahthefox.com` |
| `kf-twaqi` (existing) | — | none in the repo any more | 301 every path to the same path on `taiwanair.wahthefox.com` (deployed in step 6; Firebase keeps serving it) |

Firebase redirects can't depend on the hostname, so `kf-twaqi.web.app` can't 301 to the custom
domain while serving the same content. The content therefore moves to a new site, and the old
site keeps only the redirects. The paths stay the same, so App Store Connect's current privacy
URL `https://kf-twaqi.web.app/privacy.html` lands on
`https://taiwanair.wahthefox.com/privacy.html`, and `/zh-Hant/privacy.html` and both terms
pages work the same way.

The redirects on `kf-twaqi` were deployed once (step 6) and are live. Their config
(`firebase.legacy-redirect.json`) and placeholder page (`web-legacy/`) were removed from the
repo in FOX-82; to change them again, recreate a config with the `redirects` block below
and deploy it to site `kf-twaqi`.

## Cutover runbook

Run this only after the PR is approved and merged. Each step depends on the one before it.

1. **Create the site** (once):
   ```sh
   firebase hosting:sites:create taiwanair-wahthefox --project kf-twaqi
   ```
   If the ID is taken, pick another and update `.firebaserc` (`targets.kf-twaqi.hosting.main`)
   and the CNAME below.
2. **Deploy the content** to the new site:
   ```sh
   firebase deploy --only hosting:main
   ```
   Check `https://taiwanair-wahthefox.web.app/`, `/zh-Hant/`, `/privacy.html`,
   `/zh-Hant/privacy.html`, `/terms.html`, `/zh-Hant/terms.html`.
3. **Add the custom domain**: Firebase console → Hosting → site `taiwanair-wahthefox` →
   *Add custom domain* → `taiwanair.wahthefox.com` (no redirect option).
4. **DNS** (Cloudflare, zone `wahthefox.com`), mirroring `japanesedaily` → `kf-nihongo.web.app`:

   | Type | Name | Content | Proxy |
   |---|---|---|---|
   | CNAME | `taiwanair` | `taiwanair-wahthefox.web.app` | **DNS only** (grey cloud) |

   Add any TXT record the console asks for (ownership or `_acme-challenge`) exactly as shown.
   Leave the record **unproxied**: Firebase issues the HTTPS certificate itself and can't
   while Cloudflare is proxying. `japanesedaily` is also unproxied (it resolves to Firebase's
   `199.36.158.100`).
5. **Wait for HTTPS**: the console shows *Connected*, usually within minutes and at most
   24 hours. Then check:
   ```sh
   curl -sI https://taiwanair.wahthefox.com/privacy.html | head -1          # HTTP/2 200
   curl -sI https://taiwanair.wahthefox.com/zh-Hant/privacy.html | head -1  # HTTP/2 200
   ```
6. **Only now, switch the old host to redirects** (done; the config this step used, a
   `legacy` target serving a placeholder page with a 301 from `/` and from `^/(?P<path>.*)$`
   to `https://taiwanair.wahthefox.com/:path`, is no longer in the repo):
   ```sh
   firebase deploy --config firebase.legacy-redirect.json --only hosting:legacy
   curl -sI https://kf-twaqi.web.app/zh-Hant/privacy.html   # 301, location: https://taiwanair.wahthefox.com/zh-Hant/privacy.html
   curl -sI https://kf-twaqi.web.app/                       # 301, location: https://taiwanair.wahthefox.com/
   ```
   `kf-twaqi.firebaseapp.com` is the same site, so it redirects too.
   To roll back, deploy the old content to `kf-twaqi` again (`git checkout <old sha> -- web` and
   a one-off config with `"site": "kf-twaqi"`).
7. **App Store Connect** (after step 5 passes):
   - App Privacy → Privacy Policy URL: `https://taiwanair.wahthefox.com/privacy.html`, and
     for the 繁體中文 localization `https://taiwanair.wahthefox.com/zh-Hant/privacy.html`.
   - Marketing URL (set per version, so with the next submission): `https://taiwanair.wahthefox.com/`
     (zh-Hant: `/zh-Hant/`).
   - The old URLs keep working through the 301s, so this step isn't urgent, but the new
     ones are canonical.
8. **App**: `ProView.legalURL` already points at `taiwanair.wahthefox.com`, so ship that
   build only after step 5. Older builds keep working through the 301s.

Until step 6, `kf-twaqi.web.app` still serves the old copy of `web/`. If `privacy.html` or
`terms.html` change in the meantime, deploy that site too.
