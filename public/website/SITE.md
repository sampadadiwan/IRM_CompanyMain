# caphive.com — site structure

Static HTML. No build step, no dependencies. Open any file directly or serve the
folder with any static host.

**All internal paths are relative** (`assets/css/caphive.css`, `funds.html`), so the
site works from a subdirectory, a preview URL, or the local filesystem. The only
absolute URLs in the project are the ones the specs require to be absolute:
`<link rel="canonical">`, `og:url`, `og:image`, and `sitemap.xml`. Update the host in
those if the domain changes.

## Shared assets

| File | Contents |
|---|---|
| `assets/css/caphive.css` | The whole design system — tokens, nav, buttons, cards, dark product mocks, prose/legal styles, responsive rules, reduced-motion rules. Every page links it. **Change a component here, not per page.** |
| `assets/js/caphive.js` | Progressive enhancement only: nav shadow, mobile menu, active nav link, footer year, marquee duplication, scroll reveal, odometer counters, magnetic buttons, tabs, single-open FAQ, form handling, rotating text, number ticker. Every page reads fine with JS off. |

### JS conventions (attribute-driven — no per-page scripts)

| Attribute | Effect |
|---|---|
| `<body data-page="funds">` | Highlights the matching `[data-nav="funds"]` link |
| `data-year` | Filled with the current year |
| `data-dup` | Element's inner HTML is duplicated so a marquee loops seamlessly |
| `class="reveal"` + `data-delay="1..6"` | Blur-fade in on scroll |
| `class="odo" data-value="4000"` | Odometer count-up |
| `data-tabs` + `data-tab="x"` / `data-panel="x"` | Tab switching |
| `<form data-mailto="…" data-subject="…">` | Composes a prefilled email from the field names |
| `data-rotate='["a","b"]'` | Rotating proof line |
| `data-tick="412386905" data-prefix="US$ "` | Live-looking number |

## Pages

**Products** — `products.html` (hub), `funds.html`, `portfolios.html`,
`deals-secondaries.html`, `ai-agents.html`, `integrations.html`

**Solutions** — `who-we-serve.html`, `pricing.html`

**Proof & resources** — `case-studies.html`, `resources.html`, `faq.html`, `security.html`

**AI agents** — `ai-agents.html` is the directory; each of the sixteen agents has its
own page, `agent-<slug>.html`, mirroring its internal user guide in
`docs/user_guides/agents/` (in the IRM repo, outside this folder). Directory cards
are `<details>` elements grouped by category, so several can be open at once and it
works with JavaScript off.

The directory section of `ai-agents.html` is **generated from the agent pages
themselves** — name, category, one-liner and the three facts are read out of each
page, so the index cannot drift. Re-run `scratchpad/gen_agent_index.py` after adding,
renaming or recategorising an agent page. Categories come from each page's
`chip-label`; the buckets are Onboarding, Finance, Portfolio, Deals, Data.

Each agent page states plainly whether it uses a model or is only checking records,
and publishes its guide's failure modes rather than hiding them. **These pages are
public**: they describe internal app navigation (Admin → Edit Entity → Support
Agents), schedule times, model names and known gaps. That is appropriate for a user
guide but worth a deliberate decision before launch.

**Blog** — `blog.html` (index) and six posts: `operational-alpha.html`,
`ai-is-ready.html`, `portfolio-real-time-insight.html`, `ai-agent-infrastructure.html`,
`ai-and-fifa-2026.html`, `tech-powered-portfolio-management-vc.html`

**Company** — `about.html`, `contact.html`, `thank-you.html`

**Legal & utility** — `privacy.html`, `terms.html`, `cookies.html`, `404.html`,
`robots.txt`, `sitemap.xml`

**Home** — `index.html`

`index.html` is the homepage (formerly `modern.html`, promoted in place; the older
index design it replaced has been discarded). It is the reference for tone and visual
language, and it is the one page that keeps its own inline `<style>` and `<script>`,
because its hero animation, scrollytelling product story, agent chat and ticker are
homepage-only. It links `assets/css/caphive.css` **before** that inline block, so the
shared system supplies the nav dropdown and five-column footer while the inline rules
win on anything they both define.

It deliberately does **not** load `assets/js/caphive.js` — its own inline script
already handles the nav, mobile menu, reveals, odometers and marquees, and loading
both would double-bind those handlers.

## Asset caching — read this before you change the CSS

The Rails middleware serves everything under `public/website` with
`cache-control: public, max-age=86400`, so a browser keeps `caphive.css` for a
day. HTML is `no-store`, so page edits show up immediately but **stylesheet edits
do not** — which reads exactly like "the change didn't work".

Both shared assets are therefore linked with a content hash
(`assets/css/caphive.css?v=6e5b0c2a`). **After editing the CSS or JS, run:**

```sh
./restamp-assets.sh
```

It recomputes both hashes and rewrites the links across every page. Forgetting it
means your change is invisible for 24 hours to anyone who has already loaded the
site.

## Before launch

1. **Work through the `TODO` comments.** Every unverified claim is marked inline.
   `grep -rn "TODO" *.html` lists them. The ones that matter most:
   - Certifications and security claims (`security.html`, and the trust strip on
     several pages) — nothing there should ship unconfirmed.
   - Legal pages are **unreviewed templates** with `[bracketed placeholders]` and a
     visible warning callout. Counsel must review before publishing; delete the
     callouts afterwards.
   - Case-study outcome figures are illustrative, carried over from the homepage.
   - Leadership cards on `about.html` and the testimonials sections are `hidden`
     with placeholder content — fill them in and remove the `hidden` attribute.
   - Login is a non-navigating `<button>` (`.login`) that only opens the
     `.nav-menu` dropdown on hover/focus — it carries no `href`/`data-login` and
     the region-rewrite JS that used to target it has been removed from both
     `assets/js/caphive.js` and the homepage's inline script. The two dropdown
     items, "Login — IND" (`https://app.caphive.com/`) and "Login — USA"
     (`https://app.caphive.us/`), are the only things in that menu that actually
     navigate anywhere; add any new regional login link there directly.

2. ~~**Wire the forms.**~~ **Done.** Both demo forms POST to our own `/website_leads`
   endpoint on the app host, which stores the lead and emails the support mailbox.
   The target is resolved from the current hostname in `_partials/site_config.html.erb`,
   so caphive.com and caphive.us each reach their own stack; an unrecognised host
   falls back to the old `mailto:` draft. Handler lives in `assets/js/caphive.js`,
   duplicated in `_partials/index_scripts.html` for the homepage. See
   `docs/modules/website/website_lead_capture.md`.

3. ~~Add `og.png`~~ **Done.** 1200×630 at the site root, rendered from
   `assets/og-source.html` with headless Chrome so it uses the real Geist and
   Instrument Serif faces. Regeneration command is in a comment at the top of
   that file. Re-render it if the tagline or the headline metrics change.

4. **Configure the host** to serve `404.html` for not-found responses.

5. **Blog.** Built. Posts are flat files at the root (`operational-alpha.html`, not
   `blog/operational-alpha.html`) so every page shares one nav and footer with no `../`
   variant to maintain. A post is two stacked white cards — intro then body — using
   `.article-hero`/`.hero-panel` and `.article-card`/`.article-measure`/`.prose`.

   **Every post is a draft carrying a `DRAFT FOR REVIEW` comment and contains no
   statistics.** No percentages, figures, survey results or third-party names were
   invented; where a citable number would strengthen a claim there is a TODO comment.
   Bylines are firm-attributed with a TODO to swap in real authors. The FIFA piece
   deliberately makes no factual claim about sport at all and says so in a callout.

   `blog.html` is generated from the post files so the index cannot disagree with them
   about title, date, category, reading time or standfirst. The generator lives at
   `scratchpad/gen_blog.py`; to add a post, append its filename to `ORDER` and re-run,
   or edit both by hand and keep them in step. Reading times are measured at 225 wpm,
   not estimated.
