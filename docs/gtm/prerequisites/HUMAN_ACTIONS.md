# Human Actions — Exactly What Must Be Done by a Person

Every checklist row that an agent cannot close, with the precise action, who must do it, and what it costs. Ordered by what unblocks the most.

**Why each of these is blocked:** they require a payment method, a credential, a domain registration, a legal signature, or a business decision. None is blocked on engineering.

---

## Tier 1 — Blocks outbound at full volume. Do these first.

### C1 · Register the secondary sending domain — ~$15/yr · 15 min · **Founder**

Never send cold volume from `caphive.com`. A spam-complaint spike on the primary domain also takes down customer notification email, and domain reputation does not recover on any useful timescale.

1. Register a lookalike at any registrar (Cloudflare Registrar is at cost). Candidates in the GTM doc: **`caphive.io`**. Others: `caphive.co`, `getcaphive.com`, `caphive-hq.com`.
2. Prefer `.io`/`.co` over hyphens or extra words — a hyphenated domain in the From address is itself a spam signal to a human reader.
3. **Do not** point this domain at the website. It sends mail; it should serve, at most, a one-page redirect to `caphive.com`.

> **Interaction with B5:** outbound *sends from* the secondary domain but every link in the email points at `caphive.com`. See [`B5_utm_convention.md`](B5_utm_convention.md) §6.

### C2 · Create 2–3 mailboxes on the secondary domain — ~$20/mo · 30 min · **Founder**

Google Workspace or Microsoft 365. Two or three real, named human mailboxes — not `sales@` or `info@`, which reply-rate poorly and look automated.

Each mailbox sends **~30/day maximum**. Three mailboxes × 30/day × 5 days ≈ 450/week capacity, comfortably above the 150–200/week the plan calls for. That headroom is deliberate: sending at capacity is itself a spam signal.

### C3 · Configure SPF, DKIM and DMARC on the secondary domain — free · 1 hr · **Founder or whoever holds DNS**

**Requires DNS access. Cannot be done by an agent.**

| Record | Type | Value |
|---|---|---|
| SPF | TXT @ | `v=spf1 include:_spf.google.com ~all` (Google) or `include:spf.protection.outlook.com` (M365) |
| DKIM | TXT | Generated in the mail provider's admin console — Google Workspace: Apps → Gmail → Authenticate email → Generate new record |
| DMARC | TXT `_dmarc` | Start at `v=DMARC1; p=none; rua=mailto:dmarc@caphive.com` |

Move DMARC to `p=quarantine` only after two weeks of clean aggregate reports. Starting at `p=reject` on a new domain will silently bin your own mail.

**Test:** send to a Gmail address, open the message, *Show original*, confirm **SPF: PASS, DKIM: PASS, DMARC: PASS**. All three. This same test closes part of C6 §6.

### C4 · Warm the domain up — free (or bundled with C5) · **2–3 weeks elapsed, ~10 min/day** · **Founder**

This is why Group C starts in Phase 0. It is calendar time that cannot be compressed.

Ramp: day 1–3 ≈ 5/day per mailbox → day 4–7 ≈ 10 → week 2 ≈ 20 → week 3 ≈ 30. Most sequencers (Instantly, Smartlead) include automated warm-up pools; use it. Watch bounce rate (**keep under 2%**) and spam complaints (**under 0.1%**). If either spikes, stop ramping and hold for a week — do not push through it.

### C5 · Buy the email finder + sequencer — **$50–100/mo · requires a payment method** · **Founder**

Two functions, sometimes one tool:

| Function | Options | ~Cost |
|---|---|---|
| Email finding + verification | Hunter.io, Apollo.io, Findymail | $30–50/mo |
| Sequencing + warm-up + suppression | Instantly, Smartlead, lemlist | $30–60/mo |

**Selection criterion that actually matters:** the sequencer must support **account-level** unsubscribe suppression, not per-sequence. Confirm before paying — this is the C6 done-when test and several tools fail it by default. See [`C6_outbound_email_template.md`](C6_outbound_email_template.md) §6 for the exact test.

Verified end-to-end on one test account = row done.

### A1 · ~~Choose and configure the form endpoint~~ — **DONE, nothing to buy** · **Engineering**

**No account to create and no URL to paste.** The form posts to our own endpoint,
`/website_leads` on the app host, which stores the lead in our database and emails
the support mailbox. A third-party form processor was considered and rejected: it
would have put every inbound prospect's name, firm and stated problem in someone
else's database for no benefit we could not build in a day.

The endpoint is resolved in the browser from the current hostname
(`website_src/_partials/site_config.html.erb`), so caphive.com reaches
app.caphive.com and caphive.us reaches app.caphive.us — one built site, two stacks,
no per-deploy configuration.

**What is left for a human:** test it after the next deploy. From an incognito
window, submit the form on both `contact.html` and the homepage. Each must land in
the database (visible under **Website Leads** in the app), produce an email, and
leave the browser on `thank-you.html?src=demo-form` with no mail client involved.

See [`docs/modules/website/website_lead_capture.md`](../../modules/website/website_lead_capture.md).

### A2 · Confirm the notification mailbox — free · 10 min · **Founder**

The notification goes to `SUPPORT_EMAIL_TO` (falling back to support@caphive.com),
sent from `SUPPORT_EMAIL_FROM`, with the prospect's address as `Reply-To` so a reply
reaches them directly. Confirm that mailbox is one someone **actually watches**, and
add a Slack or push notification if the reply-time commitment is measured in hours.

**Test:** a submission produces an alert within 5 minutes. Re-test monthly — per the
checklist §9, a conversion path that fails quietly looks identical to a channel that
is not working.

### A3 · Create the booking link — free tier · 30 min · **Founder**

Calendly free tier, Cal.com, or Google Appointment Schedules.

- Event: **40 minutes** (matches the stated walkthrough length on the contact page — if that changes, change both).
- **Availability must be genuinely bookable in US business hours.** For an India-based team that is evenings IST. Publishing slots you cannot honour is worse than publishing none.
- Set the post-booking redirect to `https://caphive.com/thank-you.html?src=booking` — that is what fires the `booking_completed` conversion.

### A4 · Put the booking link everywhere — **mostly done** · 5 min · **Founder**

**Site: wired and switched on.** `bookingUrl` in `site_config.html.erb` is set to
`https://calendly.com/caphive-support`, and the header CTA, the mobile menu CTA,
the contact-page button and the thank-you-page button all read it. To change or retire
the link, edit that one line and run `rake website:build` — blanking it hides every
booking CTA again and sends the header button back to the contact form.

**Not wired, and must be done by hand:** the **email signature** used for outbound. Same
URL. See the signature block in [`C6_outbound_email_template.md`](C6_outbound_email_template.md) §4.

**Still to confirm (this is A3, and it is the part that matters):** that the account's
published availability is genuinely bookable in US business hours, and that the
post-booking redirect points at `thank-you.html?src=booking`. A live link onto an empty
or IST-only calendar is worse than no link.

### B1 · Create the GA4 property — free · 20 min · **Founder**

Create the property, take the Measurement ID (`G-XXXXXXXXXX`), paste into `ga4Id` in `site_config.html.erb`, rebuild, deploy. **Test:** Realtime view shows a visit from a phone on mobile data (mobile data, not office wifi — that is how you know it is not your own cached session).

### B2 · Create the LinkedIn Insight Tag — free · 20 min · **Founder**

Campaign Manager → Account Assets → Insight Tag. Take the numeric Partner ID, paste into `linkedInPartnerId`, rebuild, deploy. **Test:** Campaign Manager reports the tag as *Active*.

> **Start this early even with no ad budget.** LinkedIn will not serve a Matched Audience below ~300 members, and the audience only accumulates while the tag is live. This lag is the entire reason B is on the critical path.

### B3 · Create the Google Ads tag — free (account creation) · 20 min · **Founder**

Take the conversion ID (`AW-XXXXXXXXX`) into `googleAdsId`. If you also create a demo conversion action, put its full label (`AW-XXXXXXXXX/AbC-D_efG`) into `googleAdsDemoLabel`.

### B4 · Define the conversion events — 15 min · **Founder**

**The events already fire.** `demo_form_submitted` and `booking_completed` are emitted by `assets/js/caphive.js`. What a human must do is mark them as conversions in each platform:

- **GA4:** Admin → Events → mark both as *Key events*. They appear only after firing at least once, so run a test submission first.
- **LinkedIn:** create a conversion in Campaign Manager, then add the `lintrk('track', {conversion_id: …})` call at the marked spot in `_partials/analytics.html.erb`. **Deliberately left empty** — there is no truthful ID to put there until the conversion exists.

---

## Tier 2 — Weakens conversion, does not block sending

### D1 · Case studies — **Founder** · see [`D1_case_study_gap_analysis.md`](D1_case_study_gap_analysis.md)

Blocked on customer conversations. The ask email is written and ready to send as-is.

### D2 · Reference-call commitments — **Founder**

Built into the D1 ask email as the closing question. Needs 2 customers to agree in writing.

### D3 / D4 · G2 and Capterra profiles — free · 1–2 hrs each + review-chasing · **Founder**

Requires creating vendor accounts and identity verification — cannot be done by an agent.

1. Claim the profile at g2.com/products/.../take-control and vendors.capterra.com.
2. Complete it fully: categories, screenshots, description, pricing posture.
3. Chase 3+ reviews using the follow-up email in [`D1_case_study_gap_analysis.md`](D1_case_study_gap_analysis.md) §4.

Both platforms review-gate profiles, so **allow 2–4 weeks** from claim to a searchable profile with reviews. Start early; it is pure calendar time.

### D5 · Publish case studies with their own URLs — **already satisfied structurally**

All six existing case studies have their own URL and are linkable. D5 becomes truly done when the D1 upgrades land on those same URLs.

### E3 · DPA template — **requires counsel. BLOCKED.**

Needs a lawyer, not a draft. Give counsel:
- [`E4_subprocessor_list.md`](E4_subprocessor_list.md) — they need the actual subprocessor list to draft the annex
- The hosting regions and data-residency position from [`E1_security_page_content.md`](E1_security_page_content.md)
- The question of which entity signs (interacts with G1)

Ask specifically for: a **GDPR Art. 28 processor agreement with a subprocessor annex and SCCs**, since data moves between the EU/US and India. US state privacy laws (CCPA/CPRA) need a service-provider addendum. Budget ~$1–3K, or use a reviewed template.

### E5 · Stated US-hours support commitment — **a business decision, not a writing task**

The GTM doc §8 proposes *"support until 2pm ET"* — India evening, and honest.

**Decide, then publish:** actual hours, response-time targets by severity, and the channel. Then make it consistent across the security page, the contact page, and the SLA in any contract. `website_src/pages/contact.html` currently carries a `TODO` on exactly this and routes support to `hello@caphive.com` as an interim.

**Do not publish hours you will not staff.** A missed 9am ET capital-call escalation confirms the objection the whole plan exists to defuse.

---

## Tier 3 — Fast-follow

### G1 · US entity — ~$500–1K · 1–2 weeks · **Founder + counsel**

Delaware LLC or C-corp via Stripe Atlas / Clerky / Firstbase, plus a registered agent and an EIN (4–6 weeks for a foreign founder without an SSN, so start the EIN early even if the entity waits).

**Do not block outreach on this.** Start when the first deal reaches legal review. Note the dependency: C6's email footer and E3's DPA both need to know which entity is contracting.

---

## Summary

| Row | Blocked on | Cost | Owner |
|---|---|---|---|
| A1, A2 | Account creation | free tier | Founder |
| A3, A4 | Account creation + a real availability decision | free tier | Founder |
| B1, B2, B3, B4 | Account creation | free | Founder |
| C1 | Domain registration | ~$15/yr | Founder |
| C2 | Mailbox purchase | ~$20/mo | Founder |
| C3 | **DNS access** | free | DNS holder |
| C4 | **2–3 weeks calendar time** | free | Founder |
| C5 | **Payment method** | $50–100/mo | Founder |
| C6 | C5 + a live suppression test | — | Founder |
| D1, D2 | **Customer conversations** | free | Founder |
| D3, D4 | Vendor account + identity verification | free | Founder |
| E3 | **Counsel** | $1–3K | Counsel |
| E5 | **A staffing decision** | — | Founders |
| G1 | Entity formation | ~$500–1K | Founder + counsel |

**Cheapest path to "outbound can start":** C1 + C2 + C3 (~1.5 hrs and ~$35) starts the C4 warm-up clock. Everything in A and B is free-tier account creation with the code already written, and can be done inside the warm-up window at no cost to the timeline.
