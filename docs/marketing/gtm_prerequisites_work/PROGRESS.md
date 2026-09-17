# GTM Prerequisites — Working Log

**Covers:** every row of [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md), A1 → G1
**Last updated:** 2026-08-16
**Legend:** ✅ DONE · 📝 DRAFTED (human approval only) · 🔴 BLOCKED-NEEDS-HUMAN · ⬜ NOT STARTED

---

## ⚠ Read first

**[`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md)** — the live security page claims **SOC 2 Type II** and **ISO 27001:2022 certification** with no supporting evidence anywhere in the repository, and **"TLS 1.3"** which the load-balancer configuration contradicts. Separately, `cookies.html` states the authenticated app runs no analytics while the app in fact loads Google Analytics and Microsoft Clarity session recording — tagged with the client fund's name.

The GTM plan's strategy is to *volunteer* the security pack to prospects' GCs before they ask. **Volunteering an unsubstantiated certification claim is materially worse than having no security page.** This is the most urgent item in this folder and it outranks every other row.

---

## Headline results

| | |
|---|---|
| **F3 answered** | **1,354 US GPs match the §1.1 profile.** Plan needs 400–600 — the pool is 2.3–3.4× the requirement. Computed from real SEC data and verified twice. The funnel's volume assumption holds. |
| **Website conversion path** | Built and building cleanly in an isolated worktree. Form POST, thank-you redirect, booking-link wiring and analytics slots are all code-complete — **waiting only on account IDs a human must paste in.** |
| **Security pack** | Drafted from repo evidence — and the drafting surfaced the claims problem above. |

---

## Group A — Conversion path

| # | Item | Status | Detail |
|---|---|---|---|
| **A1** | Demo form POSTs to something we control | ✅ **BUILT** | Both demo forms (contact.html and the homepage) POST to our own `/website_leads` endpoint on the app host, which stores a `WebsiteLead`, emails the support mailbox with the prospect's address as `Reply-To`, and redirects to `thank-you.html?src=demo-form`. Honeypot, time-to-submit check and a 5/hour/IP Rack::Attack throttle guard it; leads are readable in-app under **Website Leads** (`:support`/`:super` only). No third-party form processor is involved — nothing to sign up for. Falls back to the old mailto behaviour only on a host `site_config.html.erb` does not recognise. <br>**Correction to the earlier note here:** an app-side endpoint was previously recorded as rejected on the grounds that `lib/middleware/website.rb:94-96` returns 405 for non-GET and nginx serves the apex directly. That reasoning was wrong — both are scoped to hosts in `WEBSITE_HOSTS`, and `app.caphive.com` is not one of them, so neither the middleware nor nginx needed changing. See [`docs/technical/website_lead_capture.md`](../../technical/website_lead_capture.md). |
| **A2** | Notification to a monitored inbox | 🔴 **BLOCKED** | Depends on A1's provider. Form POST already appends `_subject` (with firm name) and `_source_page` so the notification is triageable without opening the site. |
| **A3** | Booking link live | ⚠️ **LIVE — availability unverified** | `bookingUrl` is set to `https://calendly.com/caphive-support`, which resolves. What has NOT been confirmed is the thing A3 actually gates: that the published slots are **genuinely bookable in US business hours** (evenings IST for an India-based team). Publishing slots we cannot honour is worse than publishing none — check the availability rules on the account, and set the post-booking redirect to `thank-you.html?src=booking` so the conversion fires. |
| **A4** | Booking link in 3 places | ✅ **BUILT** | Header CTA, mobile-menu CTA, contact-page button and thank-you-page button all read `window.CAPHIVE.bookingUrl` and stay hidden while it is empty. The homepage runs `_partials/index_scripts.html` instead of `caphive.js`, so it carries its own copy of the swap — without it the busiest page on the site would have been the one page whose CTA never updated. **The email signature is not wired** and must be updated by hand — see [`C6_outbound_email_template.md`](C6_outbound_email_template.md) §4. |
| **A5** | Distinct thank-you page | ✅ **DONE** | `thank-you.html` already existed at its own URL with `robots: noindex`. Now reached as `?src=demo-form` / `?src=booking`, which is what makes it usable as a conversion trigger, and carries a booking CTA for the highest-intent moment on the site. |

## Group B — Measurement

| # | Item | Status | Detail |
|---|---|---|---|
| **B1** | Web analytics sitewide | 📝 **DRAFTED — slot built** | GA4 loader in `_partials/analytics.html.erb`, gated on `ga4Id`. Human pastes the Measurement ID. |
| **B2** | LinkedIn Insight Tag | 📝 **DRAFTED — slot built** | LinkedIn's own snippet structure, gated on `linkedInPartnerId`. The `<noscript>` pixel is deliberately omitted — it would fire for no-JS visitors regardless of configuration. |
| **B3** | Google Ads tag | 📝 **DRAFTED — slot built** | Gated on `googleAdsId`; shares the gtag loader with GA4 when both are on. |
| **B4** | Conversion events | 📝 **DRAFTED — events fire** | `demo_form_submitted` and `booking_completed` are emitted via `window.caphiveTrack()`. Three trigger paths: form POST success, `thank-you.html?src=` landing (the reliable one — a redirect can cut a beacon short), and Calendly `postMessage` for embedded widgets. Human must mark them as key events/conversions in each platform. **The LinkedIn `conversion_id` call is deliberately left as a commented no-op** — there is no truthful ID until the conversion is created. |
| **B5** | UTM convention | ✅ **DONE** | [`B5_utm_convention.md`](B5_utm_convention.md). Closed lists for source/medium, `<quarter>-<motion>-<segment>` campaign naming, worked examples, and five rules that stop it decaying. **The demo form already forwards `utm_*` params into the submission**, so a reply can be attributed to the sequence that produced it. |

**No third-party script loads while the IDs are blank.** That is deliberate — it keeps the cookie banner honest and means a half-finished setup can never send traffic to the wrong property.

## Group C — Sending infrastructure

| # | Item | Status | Detail |
|---|---|---|---|
| **C1** | Secondary sending domain | 🔴 **BLOCKED** | Domain registration, ~$15/yr. |
| **C2** | 2–3 mailboxes | 🔴 **BLOCKED** | Purchase, ~$20/mo. |
| **C3** | SPF/DKIM/DMARC | 🔴 **BLOCKED** | Requires DNS access. Exact records given in [`HUMAN_ACTIONS.md`](HUMAN_ACTIONS.md) §C3. |
| **C4** | Domain warm-up | 🔴 **BLOCKED** | **2–3 weeks of calendar time** that cannot be compressed. This is why Group C starts in Phase 0. Ramp schedule and thresholds in HUMAN_ACTIONS. |
| **C5** | Email finder + sequencer | 🔴 **BLOCKED** | Requires payment. **Selection criterion that matters: account-level (not per-sequence) unsubscribe suppression** — several tools fail this by default, and it is the C6 done-when test. |
| **C6** | CAN-SPAM template | 📝 **DRAFTED** | [`C6_outbound_email_template.md`](C6_outbound_email_template.md) — four-email sequence, all five CAN-SPAM obligations mapped, postal address and unsubscribe placeholders in every footer, merge fields mapped to real ADV columns. <br>**Cannot be closed by drafting:** the done-when test is a live unsubscribe-suppression test requiring C5. Exact test procedure in §6. <br>**Two open items:** the NY address has the shape of a virtual/CMRA suite — confirm it receives mail; and which entity name goes above it depends on G1. |

## Group D — Proof assets

| # | Item | Status | Detail |
|---|---|---|---|
| **D1** | 2–3 case studies with hard numbers | 🔴 **BLOCKED** | [`D1_case_study_gap_analysis.md`](D1_case_study_gap_analysis.md). **Six case studies already exist and none satisfies D1.** Retargeted per coordinator instruction to a gap analysis plus a ready-to-send customer ask, not new prose. Key finding: **there is exactly one improvement claim across all six pages** (`over 5× more efficient`, on investor-statements) and it has no baseline; two pages have literal `Before:`/`After:` headings containing **no numbers at all**. Cheapest win identified: the same page says the quarter *"used to take a fortnight"* and never gives the after figure. |
| **D2** | 2 reference-call commitments | 🔴 **BLOCKED** | Built into the D1 ask email as the closing question. |
| **D3** | G2 profile + 3 reviews | 🔴 **BLOCKED** | Vendor account + identity verification. Allow 2–4 weeks; start early, it is pure calendar time. |
| **D4** | Capterra profile + 3 reviews | 🔴 **BLOCKED** | As D3. |
| **D5** | Case studies published with own URLs | ✅ **DONE (structurally)** | All six already have their own URL and are linkable. Becomes fully true when D1 upgrades land on those same URLs. |

**Blocking dependency (GTM §11):** whether current customers are usable as *US* references is unresolved. The D1 ask email is written to answer it in the same conversation.

## Group E — Security pack

| # | Item | Status | Detail |
|---|---|---|---|
| **⚠** | **Claims audit** | ✅ **DONE — urgent** | [`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md). Unsupported SOC 2 / ISO 27001 claims, contradicted TLS claim, unconfirmed database-volume encryption, and a cookie policy the product falsifies. Nine required actions, ordered. |
| **E1** | Security page | 📝 **DRAFTED** | [`E1_security_page_content.md`](E1_security_page_content.md) — replacement content where every claim traces to a file, and gaps appear as explicit `TODO-VERIFY` rather than silence. Includes a certifications section that says "we do not have SOC 2" and turns that into a trust asset. |
| **E2** | Pre-completed questionnaire | 📝 **DRAFTED** | [`E2_security_questionnaire.md`](E2_security_questionnaire.md) — SIG Lite / CAIQ domain structure, ~60 questions across 9 domains. 🔴-marked answers must not be sent until verified. Pre-send checklist at §J. |
| **E3** | DPA | 🔴 **BLOCKED — counsel** | Needs a lawyer, not a draft. The subprocessor list is the input to the annex; instructions for counsel in [`HUMAN_ACTIONS.md`](HUMAN_ACTIONS.md). |
| **E4** | Subprocessor list | 📝 **DRAFTED** | [`E4_subprocessor_list.md`](E4_subprocessor_list.md) — ~27 real subprocessors, each with the proving file. **The current `privacy.html` placeholder taxonomy omits AI/LLM providers entirely**, which for CapHive is the most sensitive category. Three entries need a business decision before publication (GA4, Clarity, QuickChart). |
| **E5** | US-hours support commitment | 🔴 **BLOCKED** | A staffing decision, not a writing task. Do not publish hours that will not be staffed. |

## Group F — Target list

| # | Item | Status | Detail |
|---|---|---|---|
| **F1** | ADV bulk data downloaded | ✅ **DONE** | 2026-06-01 vintage, 16,876 advisers × 448 columns, in `tmp/adv_data/` (gitignored). Working URL and the blocked-host trap documented in [`F_form_adv_findings.md`](F_form_adv_findings.md) §6. |
| **F2** | Filter applied | ✅ **DONE** | Re-runnable script at [`scripts/adv_filter.py`](scripts/adv_filter.py) — stdlib-only, resolves columns through candidate lists so an ADV vintage rename fails loudly instead of producing a wrong number. Outputs `adv_icp_matches_us.csv` (1,354 rows). |
| **F3** | **Sanity check pool size** | ✅ **DONE** | **1,354 US firms match. Requirement is 400–600. The assumption holds with 2.3–3.4× headroom** — F3's contingency branch does not fire. Verified twice with independently chosen columns. Median match: $807M RAUM, 6 private funds. <br>**Additional finding:** §1.1 claims the complexity qualifier "costs nothing extra to target" because ADV carries it. **Only half true** — ADV carries vehicle count precisely, but SPV/parallel-fund and side-letter qualifiers are not in the data. Closest proxy (2+ distinct fund types) still yields **411 accounts**, itself inside the requirement — giving a clean Tier 1 / Tier 2 list strategy. |
| **F4** | First 100 accounts researched | ⬜ **NOT STARTED** | Human research work, unblocked by F1–F3. Needs C5 tooling for email verification. **17–25 hours at the plan's own 10–15 min/account rate — this is the real Phase 0 critical path, not the website work.** |

**Contact data is better than the plan assumed:** 100% of the 1,354 have a phone number and 95% have a website, straight from ADV at zero cost.

## Group G — Legal and admin

| # | Item | Status | Detail |
|---|---|---|---|
| **G1** | US entity | 🔴 **BLOCKED** | Entity formation, ~$500–1K. Correctly a fast-follow — do not block outreach. **Two dependencies to note:** C6's email footer and E3's DPA both need to know which entity is contracting. |

---

## Website worktree — for review, uncommitted

**Path:** `/home/thimmaiah/work/IRM-gtm-prereqs`  **Branch:** `gtm/website-prereqs`  **Nothing committed** — all changes are uncommitted in the working tree, as instructed.

### Source changes (7 files — this is the real diff)

| File | Change |
|---|---|
| `website_src/_partials/site_config.html.erb` | **NEW.** The one file a human edits. Six config values, every one shipping empty, each with a `TODO-HUMAN` comment explaining exactly what to paste and where to get it. **No invented IDs.** |
| `website_src/_partials/analytics.html.erb` | **NEW.** GA4 / LinkedIn / Google Ads slots, each gated on its own ID. Defines `window.caphiveTrack(name, params)` unconditionally so page code never needs to know which vendors are on. |
| `website_src/_layout.html.erb` | Renders both partials in `<head>`, config first. 4 lines. |
| `public/website/assets/js/caphive.js` | The substantive change. Replaced the ~24-line mailto-only forms block with a ~140-line conversion-path block: dual-mode form handling, UTM forwarding, booking-link wiring, query-param-gated conversion events, Calendly `postMessage` listener. <br>*Assets are not templated — `lib/tasks/website.rake:16-17` states they live in `public/website` and are the source for JS/CSS. Editing here is correct.* |
| `public/website/assets/css/caphive.css` | `.booking-alt` rule for the booking CTA row (~20 lines). No inline styles added. |
| `website_src/pages/contact.html` | Form gets an `id`, a `data-posted-note`, and a hidden booking block. Misleading copy is now swapped by JS when a real endpoint is configured, so the page never claims to have sent something it has not. |
| `website_src/pages/thank-you.html` | Hidden booking CTA + a comment documenting the `?src=` conversion contract. |
| `_partials/nav.html.erb`, `_partials/mobile_menu.html` | `data-booking-cta` on the header CTAs (1 line each). |

### Generated output

64 `public/website/*.html` files regenerated by `rake website:build`. Every page changed because the two new head partials are sitewide. **`public/website/` was never hand-edited.**

**Build verified:** `website: built 64 pages`, no errors. Confirmed in the output that `window.CAPHIVE` is present, the booking blocks render hidden, `data-booking-cta` is on the nav, and **no third-party tag fires while the IDs are blank**.

### Review notes

- The `git status` list looks alarming (71 files) but 64 are generated. **Review the 7 source files.**
- Behaviour is unchanged for a visitor until a human fills in `site_config.html.erb`. This is safe to merge before any account exists.
- No application code was touched.

---

## What is genuinely finished vs. waiting

**Finished and needs nothing:** B5, F1, F2, F3, A5, the security claims audit.

**Code-complete, waiting on one paste each:** A1, A4, B1, B2, B3, B4. Roughly **two hours of free-tier account creation** converts six checklist rows from blocked to done.

**Blocked on money:** C1, C2, C5 (~$70–130/mo + ~$15 one-off).
**Blocked on calendar:** C4 (2–3 weeks), D3/D4 (2–4 weeks).
**Blocked on other people:** E3 (counsel), D1/D2 (customers), E5 (a staffing decision), G1 (entity).

**The real critical path is not the website.** It is (a) the security claims correction, which gates every conversation with a GC, (b) C1→C4, whose 2–3 week warm-up cannot be compressed, and (c) F4's 17–25 hours of contact research. All three can run in parallel starting today.
