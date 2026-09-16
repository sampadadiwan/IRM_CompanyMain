# Website pre-launch TODOs

Audit of `website_src/` (57 pages) on 2026-08-09. Counts are from the sources, not
from memory — re-run them with `grep -c TODO website_src/pages/*.html`.

| | |
|---|---|
| TODO markers in the copy | **111** across 25 of 57 pages |
| Of those, "VERIFY before launch — do not publish unless confirmed" | **40** |
| Pages with no TODOs at all | 33 |
| Dead links (`href="#"`) | 14, across `careers`, `index`, `case-studies` |

---

## 1. Blockers — published claims that could mislead

These are assertions a reader would take as fact. The pages themselves flag them as
unverified, which means nobody has yet confirmed them.

- **`security.html` — SOC 2 Type II.** The compliance table states "Independent audit
  and attestation: SOC 2 Type II", wrapped in `TODO: VERIFY before launch — do not
  publish unless confirmed by CapHive`. If the report does not exist, this is a false
  compliance claim on a page investors will read. 36 TODO markers on this page alone.
- **`security.html` — hosting regions and data residency.** The page's own note says the
  "regions and testing cadences referenced here have not yet been confirmed". It
  currently promises residency options for Indian and US funds.
- **`security.html` — penetration testing.** Cadence stated but unconfirmed.
- **`cookies.html` — consent.** Carries an explicit `TODO — DEV, BLOCKING FOR LAUNCH`
  and a note that consent must be obtained before the behaviour described in section 5.
  There is also an `ENGINEERING` TODO to verify the callout against what the site
  actually sets.
- **Headline metrics** — `US$ 10bn+ AUM`, `4,000+ investors`, `US$ 500m+ raised &
  secondaries`, `1,000+ sellers & investors`. Used in the nav chip, the OG image and
  eight pages. These need one owner signing off on each figure.

## 2. Accuracy against the product documentation

Checked the site's feature claims against `docs/user_guides/` (52 guides + 16 agent
guides).

- **"Shadow books" has no product behind it.** The phrase appears on **9 website pages**
  ("waterfalls and shadow books on one ledger", "shadow books current every day") and
  has **zero** occurrences in the user guides, the models, or the services. Either it is
  marketing shorthand for running CapHive in parallel with an administrator — in which
  case say that, since the FAQ already describes it that way — or it names a capability
  that needs a guide. As written a prospect will ask for a feature nobody can demo.
- **`integrations.html`** — 9 TODOs, including "confirm which of these integrations are
  live today vs. on the roadmap" and "confirm which banks are connected directly today
  before naming any of them here". Naming a bank that isn't connected is the most
  concrete misinformation risk on the site.
- **`case-studies.html`** — 9 TODOs. Outcome figures are explicitly illustrative and the
  quotes/names are placeholders carried over from the old site.
- **`faq.html`** — 6 TODOs covering supported structures, jurisdictions and regulatory
  regimes, the exact model handling, and implementation timelines.

**What checked out clean:** the "sixteen agents" claim is accurate. All 16 agent pages
map 1:1 to a guide in `docs/user_guides/agents/`, with no extras on either side.

## 3. Information gaps

- **Leadership** — `about.html` has four placeholder cards awaiting real names, roles
  and one-liners.
- **Careers** — placeholder roles; every role links to `href="#"`; no ATS. TODO suggests
  deleting the section if there is no pipeline to point at.
- **Pricing** — "insert real pricing or keep this quote"; implementation ranges by fund
  count and module are unconfirmed.
- **Mailboxes** — the site references support, security and careers inboxes that may not
  exist. Needs: a real support mailbox with stated hours, a security disclosure mailbox
  and policy, and a careers inbox (or reuse `hello@`).
- **Blog** — article titles can't link anywhere yet ("link the title above to the
  article once blog article pages exist"). The blog index and `sitemap.xml` are both
  hand-maintained.
- **Offices** — a second card is needed if there is a US registered entity.
- **Demo length** — "40 minutes is our current intent, not a confirmed figure."

## 4. Functionality that isn't wired

- **Contact form** (`contact.html`, `index.html`) falls back to a `mailto:`. Needs a POST
  to the CRM or a form endpoint.
- **Mailing list** block opens an email to the shared inbox; there is no list behind it.
- **14 dead `href="#"` links** across careers, index and case-studies.

## 5. Build and assets

- **Logo is undecided.** The nav and footer currently run the original script-face PNG
  (`caphive-logo-original.png`) as a trial. The alternative is the generated Geist
  lockup (`caphive-logo.svg`), which matches the site's typography. Pick one.
- **`apple-touch-icon.png` is missing** — iOS home-screen bookmarks fall back to a
  screenshot. `caphive-mark.svg` is there to generate it from.
- **`assets/og-source.html` is served publicly.** It is a build artifact for `og.png`,
  not a page. Move it under `website_src/`.
- **Assets aren't in the source tree.** `assets/css`, `assets/js` and `assets/img` still
  live in `public/website/`; only HTML is generated. Fine for now, worth revisiting.
- **Nothing is deployed.** `og.png`, the new headline, the logo and every content change
  since the last release are local only — they need `cap staging_in deploy`.

## 6. Infrastructure

- **No ALB listener on port 80.** `http://altconnects.com` fails to connect entirely
  (so does `www` and `dev`). Needs a `:80 → :443` redirect listener plus port-80 ingress
  on the ALB security group, in `IRM-Infra/alb.py`.
- **Production apex isn't pointed at the app.** `caphive.com` still resolves to the
  GoDaddy Website Builder IP `68.178.153.117`; `caphive.us` has no apex record at all.
- **ACM certificates** need apex SANs on both production stacks — the existing certs are
  wildcard-only.
- **`cap production_in nginx:update` / `cap production_us nginx:update`** have not been
  run, so neither production stack serves the website vhost yet.

---

## Suggested order

1. Section 1 in full — nothing ships while an unverified SOC 2 claim is on the page.
2. Section 2's integrations and "shadow books" wording — same risk class, cheaper to fix.
3. Section 4, then 3 — a visitor who wants to talk to you currently can't.
4. Sections 5 and 6 together, as one deploy.
