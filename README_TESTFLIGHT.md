# US Trail Water Analysis — iOS / TestFlight package

A complete Flutter app that ports the GPX water-source analyzer to run **on the
phone**, against the same free, keyless USGS / NRCS / OpenStreetMap / NWS data.
This document gets it onto **TestFlight without a Mac or Xcode**, using
Codemagic's cloud macOS build machines.

- **App name (on the Home Screen):** `US Trail Water Analysis`
- **Bundle identifier:** `com.ustrailwater.usTrailWaterAnalysis`
- **What it does:** load a GPX route, optionally reverse it, and list every
  water crossing by trail and mile with a flowing-or-dry call grounded in
  current snowpack, streamflow, and drought conditions. Tap **Demo** to try it
  with a bundled Colorado foothills route.

Everything below is do-able entirely on Windows in a browser. The only paid
requirement is the **Apple Developer Program ($99/year)** — Apple requires it
for TestFlight, and there is no way around that.

---

## What's in this package

```
us_trail_water_analysis/
  lib/
    main.dart                 Home screen (pick GPX, reverse, date, analyze)
    result_page.dart          Results UI (headline, sources, conditions, share)
    analysis/                 The analyzer, ported 1:1 from gpx_water_analysis.py
      net.dart                cached HTTP with retry/backoff
      geometry.dart           haversine, mileage, bbox, segment intersection
      gpx.dart                GPX parse + reversed-GPX builder
      hydrology.dart          USGS NHD crossings, clustering, elevation
      osm.dart                OpenStreetMap Overpass trail/stream names
      conditions.dart         NLDI, NWIS, NRCS forecast+snowpack, drought, NWS
      classify.dart           flowing/dry classification + dry-year logic
      analyzer.dart           orchestration
      report.dart             markdown report (for Share)
      models.dart             typed result models
  assets/demo/reynolds-demo.gpx   bundled demo route
  test/                       widget + logic tests
  tool/logic_check.dart       offline logic smoke test (dart run tool/logic_check.dart)
  ios/                        native iOS Runner (display name already set)
  codemagic.yaml              cloud build → TestFlight pipeline
```

The analysis is identical in behavior to the reference Python tool. A live run on
the demo route reproduces the reference dry-year signal (NRCS Apr–Jul runoff
44% of normal, April-1 snowpack ~12% of median, route drains toward the South
Platte) — the same numbers the original `water_analysis.md` reports.

---

## The big picture (why no Mac is needed)

Compiling an iOS app and uploading to TestFlight *must* happen on macOS. Instead
of owning a Mac, you rent one for a few minutes per build: **Codemagic** clones
your repo onto a cloud Mac, runs `flutter build ipa`, signs it with your Apple
credentials, and uploads it to TestFlight. You drive the whole thing from a
browser. (Alternatives that work the same way: GitHub Actions `macos` runners,
Bitrise, or `flutter build ipa` on any rented Mac-in-the-cloud. This package
ships a ready-to-go Codemagic config.)

---

## Step 0 — One-time accounts

1. **Apple Developer Program** — enroll at <https://developer.apple.com/programs/>
   ($99/year). Wait until it's active. You need the **Account Holder** or
   **Admin** role.
2. **A Git host** — a free GitHub account (or GitLab/Bitbucket).
3. **Codemagic** — sign up free at <https://codemagic.io> and log in with your
   Git host so it can see your repos.

---

## Step 1 — Put this project in a Git repository

On your Windows machine, in this folder
(`C:\Users\santi\Documents\us_trail_water_analysis`):

```powershell
git init
git add .
git commit -m "US Trail Water Analysis iOS app"
```

Create an empty repo on GitHub (e.g. `us-trail-water-analysis`), then:

```powershell
git remote add origin https://github.com/<you>/us-trail-water-analysis.git
git branch -M main
git push -u origin main
```

> Don't have Git? Install it from <https://git-scm.com/download/win>, or use
> GitHub Desktop. If `flutter` complained about `git` earlier, this also fixes it.

---

## Step 2 — Create an App Store Connect API key

This key lets Codemagic sign and upload on your behalf — no certificates to
juggle by hand.

1. Go to <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations**
   (a.k.a. **Keys**) → **App Store Connect API**.
2. Click **+**, name it `Codemagic`, set **Access = App Manager**, **Generate**.
3. Download the **`.p8`** file (you can only download it once) and note:
   - **Issuer ID** (shown above the keys list)
   - **Key ID** (the row you just made)

---

## Step 3 — Register the App ID and create the app record

1. **App ID:** <https://developer.apple.com/account/resources/identifiers/list>
   → **+** → **App IDs** → **App** → Description `US Trail Water Analysis`,
   Bundle ID **Explicit** = `com.ustrailwater.usTrailWaterAnalysis` → Register.
   *(You can skip this — Codemagic can auto-register it during the first build —
   but doing it yourself avoids surprises.)*
2. **App record:** <https://appstoreconnect.apple.com> → **Apps** → **+** →
   **New App**:
   - Platform: **iOS**
   - Name: **US Trail Water Analysis** *(must be unique across the App Store; if
     taken, add a suffix like “US Trail Water Analysis — Hikes”. This only
     affects the store name, not the app on the device.)*
   - Primary language, Bundle ID = the one above, SKU = `ustrailwater001`.

---

## Step 4 — Connect Codemagic and add the key

1. In Codemagic → **Add application** → pick your Git provider → select the
   `us-trail-water-analysis` repo → project type **Flutter App**. Codemagic
   detects the included `codemagic.yaml`.
2. **Teams/Personal → Integrations → App Store Connect → Connect**. Add the key
   from Step 2:
   - **Name it exactly `app_store_key`** (the `codemagic.yaml` references this
     name under `integrations:` and `ios_signing:`).
   - Paste **Issuer ID**, **Key ID**, and upload the **`.p8`** file.

That's the entire signing setup — Codemagic uses this key to fetch/create the
signing certificate and provisioning profile automatically (`xcode-project
use-profiles` in the build script).

---

## Step 5 — Run the build

1. In your Codemagic app, open the **ios-testflight** workflow → **Start new
   build** (or just `git push` — builds can trigger automatically).
2. It runs: `flutter pub get` → `pod install` → `flutter analyze` →
   `flutter build ipa` (signed) → **upload to TestFlight**. Typical time:
   8–15 minutes.
3. When it finishes green, the `.ipa` appears under **Artifacts**, and the build
   is sent to App Store Connect.

---

## Step 6 — Test on your iPhone via TestFlight

1. Install **TestFlight** from the App Store on your iPhone.
2. In App Store Connect → your app → **TestFlight** tab. The new build shows
   **“Processing”** for a few minutes, then is ready.
3. First upload only: answer the **Export Compliance** question. This app uses
   only standard HTTPS, so you can set
   `ITSAppUsesNonExemptEncryption = NO` (add `<key>ITSAppUsesNonExemptEncryption</key><false/>`
   to `ios/Runner/Info.plist` to skip the prompt on every build).
4. Add yourself under **Internal Testing** (your Apple ID is already a tester as
   an Admin). Internal testers need no Apple review.
5. Open TestFlight on the phone → install **US Trail Water Analysis** → tap
   **Demo** → **Analyze**. You'll see the water-source report within a minute.

To invite others: add their emails under **Internal Testing** (up to 100, no
review), or create an **External** group (needs a quick Beta App Review).

---

## Updating the app later

Make changes, then:

```powershell
git add .
git commit -m "what changed"
git push
```

Codemagic rebuilds and uploads a fresh TestFlight build. The build number
auto-increments from the last TestFlight build, so uploads never collide.

---

## Verifying locally before you push (optional)

You don't need a Mac to sanity-check the Dart:

```powershell
flutter pub get
flutter analyze                 # static analysis — should be clean
dart run tool\logic_check.dart  # offline logic checks — prints ALL CHECKS PASSED
```

> Note: `flutter test` may fail to run *on this Windows-on-ARM machine only*,
> because the `share_plus` plugin pulls a native `objective_c` build hook that
> needs an x64/arm64 MSVC toolchain locally. This does **not** affect the iOS
> build — Codemagic's macOS machine compiles it correctly. Use
> `dart run tool\logic_check.dart` for local verification, which exercises the
> full analyzer logic without the plugin.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build fails at signing | The App Store Connect key must be named **`app_store_key`** in Codemagic and have **App Manager** access. |
| “No matching profiles” | Make sure the bundle id in `codemagic.yaml` matches the App ID and the App Store Connect app record exactly. |
| “Bundle id not registered” | Register it in Step 3, or let Codemagic auto-register (it will on first signed build). |
| Upload says duplicate build number | Already handled by the auto-increment script; if you build manually, bump `--build-number`. |
| App on phone but analysis errors | The phone needs internet while analyzing (it queries USGS/NRCS/OSM/NWS live). |
| Want a different bundle id / org | Change it in `codemagic.yaml` **and** `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`), keep them identical. |

---

## Notes on accuracy & scope

- The analyzer judges **presence of flow**, not water quality. Backcountry water
  is not potable without treatment.
- Hydrology/conditions data is **US-only**. Outside the US the app still finds
  OSM waterways/trails and geometry but marks conditions unavailable rather than
  guessing — same behavior as the reference tool.
- Trail names come from OpenStreetMap; a route on unmapped tread reports
  `off-trail`, which is expected.
