# US Trail Water Analysis — Web App (PWA)

This is **Option A**: the app runs as an installable Progressive Web App. Anyone
opens a link in a browser and (on iPhone) taps **Share → Add to Home Screen** to
get an app icon that launches full-screen. **No Apple Developer account, no $99,
no app review, no install limits, no 7-day expiry.** Works on iPhone, iPad,
Android, and desktop.

## Status — built and verified ✅

- The analyzer was compiled to JavaScript and run in a **real headless Chrome**
  against the live APIs. Every data source works from the browser:
  USGS NHD (crossings), USGS EPQS (elevation), USGS NLDI (drains-to),
  NRCS forecast + snowpack, USGS NWIS, US Drought Monitor, NWS, OpenStreetMap.
- **No CORS proxy is needed.** 8 of the endpoints already send
  `Access-Control-Allow-Origin: *`; the two that don't (open-elevation and one
  Overpass mirror) are automatically swapped on web for CORS-enabled equivalents
  (USGS EPQS and `overpass-api.de`). This is handled by the `web: true` path in
  `lib/analysis/`.
- The production build (`build/web/`) boots with the correct title and **zero
  console errors**, and includes a service worker for offline app-shell caching.

## Try it right now, locally (no account)

```powershell
flutter build web --release
cd build\web
python -m http.server 8000
```

Open <http://localhost:8000> in Chrome/Edge. (Or just `flutter run -d chrome`.)
This is the exact app that gets published — only the public URL is missing.

---

## Publishing it (one free host account required)

A public site needs a host. Pick **one** — all have free tiers, none need a card.
The build output to upload is the **`build/web`** folder.

### Option 1 — Netlify Drop (easiest, no CLI, ~2 min) ⭐ recommended
1. Run `flutter build web --release` (already done — output is `build/web`).
2. Go to <https://app.netlify.com/drop>.
3. Drag the **`build/web`** folder onto the page. You instantly get a public
   HTTPS URL (e.g. `https://trail-water-xxxx.netlify.app`).
4. Click **Sign up** (GitHub or email, free) to claim the site so it stays up and
   you can rename it. Done.
- **Cost:** $0. **Account:** Netlify (free).

### Option 2 — GitHub Pages (free, permanent, ties in with your iOS repo)
GitHub Pages serves from a sub-path, so build with a base href that matches the
repo name:
```powershell
flutter build web --release --base-href "/us-trail-water-analysis/"
```
1. Create a GitHub repo `us-trail-water-analysis` and push the project.
2. Copy everything in `build/web` into a `docs/` folder on the `main` branch (or
   push it to a `gh-pages` branch).
3. Repo **Settings → Pages →** Source = `main` / `docs` (or `gh-pages` / root).
4. Your URL: `https://<you>.github.io/us-trail-water-analysis/`.
- **Cost:** $0. **Account:** GitHub (free). *(If you already make the GitHub repo
  for the TestFlight/Codemagic path, this reuses it.)*

### Option 3 — Cloudflare Pages or Vercel (free, CLI one-liner)
```powershell
# Cloudflare (opens browser to log in the first time):
npx wrangler pages deploy build/web --project-name us-trail-water-analysis
# or Vercel:
npx vercel deploy build/web --prod
```
- **Cost:** $0. **Account:** Cloudflare or Vercel (free).

> I can run Option 1 or 3 for you end-to-end — the only step I can't do is create
> the account / approve the browser login, which is yours to click. Tell me which
> host and I'll drive the rest.

---

## How your testers install it (iPhone)

Send them the URL. On the iPhone:
1. Open the link in **Safari** (must be Safari for Add-to-Home-Screen).
2. Tap the **Share** button → **Add to Home Screen** → **Add**.
3. The blue mountain icon "US Trail Water Analysis" appears. Tapping it launches
   full-screen, no browser chrome — looks and feels like a native app.

Android/Chrome shows an **Install app** prompt automatically.

---

## What works the same vs. native

- **Same:** the full analysis, GPX file picking, the Demo route, the results UI,
  and the Share/export of the markdown report.
- **Different:** a PWA can't be listed on the App Store and doesn't get push
  notifications on iOS (not used here). Everything this app does works in the PWA.

## Updating

Re-run `flutter build web --release` and re-deploy (drag the new `build/web`, or
re-run the CLI command, or push to the Pages repo). Testers get the update on
next launch — no reinstall.
