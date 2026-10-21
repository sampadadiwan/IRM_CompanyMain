# Tasks

> **Traceability:** every scenario carries `# <ID> — <kind>: …` from [business-rules.md](business-rules.md);
> code comments name the IDs whose path runs through them. Runs use a random `TEST_ENV_NUMBER`,
> with Redis up on 6379.

## 1. Server: sites, region switch, fund manager (① ② ③)

- [x] 1.1 `GET /api/mobile/v1/sites` (`SitesController`, public) from `SiteRegistry` (MS-H1).
- [x] 1.2 `POST /api/mobile/v1/cross_site_links` (`CrossSiteLinksController`, purpose `mobile_cross_site`) with the website's checks (MS-X1, MS-E3, MS-X3).
- [x] 1.3 `POST /api/mobile/v1/session/cross_site` → `MobileSignIn.cross_site` (MS-H3, MS-X2, MS-X4, MS-X5, MS-E4).
- [x] 1.4 `MobileFundManagers` (`list`, `resolve`) and `BaseController#fund_manager_id`; `home` and `documents` narrowed and echo `fund_manager_id` (MF-H1, MF-H2, MF-E1, MF-E2, MF-H4).
- [x] 1.5 `/me` adds `fund_managers` and `regions` (MF-H3, MS-H2, MS-E2).
- [x] 1.6 Notification JSON `sender_id`; Expo push `data.region` and `data.fund_manager_id` (MF-H5).
- [x] 1.7 `features/mobile/mobile_multi_site.feature` + `mobile_multi_site_steps.rb`; E29 in `mobile_data.feature` now expects one fund manager. Run `features/mobile/` green (92 scenarios).

## 2. App

- [x] 2.1 `src/api/config.ts`: `ENVIRONMENTS`, `customEnvironment`, `Site`; `app.config.js`: one identity for staging and production, `extra.defaultEnvironment`.
- [x] 2.2 `src/api/client.ts` + `auth/storage.ts`: one session per site, `base`/`token` options for cross-site calls.
- [x] 2.3 `auth/session.tsx`: `chooseSite`, `openSitePicker`, `switchRegion`, sign out of every site.
- [x] 2.4 Site screen (`(auth)/region.tsx`) with long-press test environments and `/sites` + fallback (MS-H1, MS-E1).
- [x] 2.5 `lib/fund-manager.tsx` + `ui/fund-manager-picker.tsx`; Home, Documents, Alerts, Fund screen use the selected fund manager (MF-*).
- [x] 2.6 Profile: Switch region card, Change site; sign-in shows the environment on test sites.
- [x] 2.7 Push taps switch region and fund manager first (MS-H5, MF-H5).
- [x] 2.8 `npx tsc --noEmit` and `npx eslint src` clean.

## 3. End-to-end and build

- [x] 3.1 Two local regions (IN :3999, US :3998, separate seeded test DBs) — API script: sign in, `/me`, Home default / Beta / no-access fallback, Documents per fund manager, alerts `sender_id`, link + redeem, same-region refusal, IN session intact after switch.
- [x] 3.2 Web build driven by Playwright: site screen → regions → sign in → Home on Arka → pick Beta → Documents → Profile → switch to US (US data) → back to India (82 ms, Beta still picked).
- [x] 3.3 `.easignore` fixed (no trailing-slash directory patterns); EAS staging Android build from this branch.
- [ ] 3.4 Deploy the server branch to staging IN and US; install the staging APK; run [qa-checklist.md](qa-checklist.md).
