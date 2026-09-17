# F4 Contact-Data Vendor Comparison

**Purpose:** Vendor options for automating the contact-resolution half of [F4](../us_gtm_prerequisites.md#7-group-f--target-list--runs-in-parallel) — turning the 1,354-row ADV-filtered firm list into named CFO/COO/Controller contacts with verified emails. Cost is intentionally ignored in this comparison to separate "what's best" from "what's affordable"; see the note at the end for the recommended affordable pick.

**Status:** Working notes, not a decision. No vendor has been selected or paid for.

---

## Comparison matrix

| Provider | What it can do | Cost (ballpark, cost ignored for ranking) | Pros | Cons |
|---|---|---|---|---|
| **Apollo.io** | People search by title + company domain; email finder with verified/guessed/unavailable confidence tags; bulk CSV/API enrichment; basic firmographic filters | ~$49–99/mo, self-serve, credit-based | Self-serve, API-first, cheapest of the group, easiest to script against the existing ADV CSV today | Coverage gaps on smaller GPs and non-owner "Head of Fund Ops" roles; zero fund-structure data (no SPV/parallel/side-letter signal) |
| **ZoomInfo** | Deep org charts, direct dials; title-level accuracy tuned by industry vertical (incl. asset management); intent data; API access (add-on tier) | ~$15K–40K+/yr, annual contract | Noticeably more accurate/fresher contact records than Apollo in financial-services verticals; direct-dial phone numbers | Enterprise sales cycle, not instant self-serve; no fund-structure intelligence; API often gated to higher tiers |
| **Cognism** | Phone-verified ("Diamond Data") contacts; GDPR-compliant sourcing; US + EU coverage; API access | ~$15K–30K+/yr, annual contract | Strong compliance posture — relevant given the foreign-LP >25% complexity signal in the ICP; high data-quality bar | Historically stronger in EU than US coverage; still no PE/fund-structure data; contract-based, not self-serve |
| **Clay** | Waterfalls one lookup across Apollo/ZoomInfo/Hunter/Clearbit/RocketReach, keeps the best match; AI-assisted lookup for edge cases; purpose-built enrichment/API pipelines | ~$150–800+/mo (subscription + underlying provider credits stack on top) | Shrinks the exact coverage gap already flagged (smaller GPs, non-owner ops titles) by not depending on one vendor; built for this kind of bulk pipeline, not adapted to it | Still inherits the underlying providers' blind spot on fund-structure data; adds an orchestration layer to manage; cost stacks across multiple sub-providers |
| **PitchBook** | Tracks fund structures directly: vintages, parallel funds, SPVs/co-invest vehicles; named fund leadership (CFO/COO/Managing Partner); AUM, fundraising, deal data | ~$20K–40K+/yr, sales-negotiated enterprise license | Only tool here that directly answers the SPV/parallel-fund gap `adv_field_mapping.md` flagged as unfillable from ADV — closes a second problem, not just contact lookup | Weak on verified personal emails — contact data is secondary to firm/deal data; no self-serve; export-based rather than API-automatable on most license tiers |
| **Preqin** | Same category as PitchBook: GP/LP profiles, fund structures, key personnel, fundraising data | ~$20K+/yr, sales-negotiated enterprise license | Same structural-data advantage as PitchBook; useful LP-side data if that becomes relevant later | Same weaknesses as PitchBook on contact/email depth; enterprise sales cycle; limited automation access |

---

## Reading the matrix

Apollo, ZoomInfo, Cognism and Clay all solve *contact resolution* with varying depth and cost. Only PitchBook and Preqin solve the *structural qualifier* problem — SPV/parallel-fund structure and side-letter counts — that [`adv_field_mapping.md`](adv_field_mapping.md) already documented as a genuine gap in Form ADV, not collected anywhere on the form and currently pushed to the discovery call. Neither PitchBook nor Preqin is a strong contact-email source on its own.

**If cost truly didn't matter:** pair PitchBook or Preqin (firm-and-structure intelligence) with Clay or ZoomInfo (the actual verified contact) — the only combination that closes both the contact gap and the complexity-qualifier gap.

**Cost-constrained recommendation (the actual next step):** Apollo.io. It's the only self-serve, API-first option in the set, fits inside a founder-approvable budget without a sales cycle, and directly targets the piece [`gtm_outbound_work/PROGRESS.md`](../gtm_outbound_work/PROGRESS.md) calls the real bottleneck — name → verified email. The structural gaps (SPV, parallel fund, side letters) stay on the discovery-call screen (`qualification_screen.md`) regardless of vendor choice; no contact-data tool, including the enterprise ones, removes that step.

---

## Open items

- No vendor has been selected. This is founder decision + payment method, same as [C5](../us_gtm_prerequisites.md) in the prerequisites checklist.
- If Apollo is chosen, next step is building the enrichment script extending [`scripts/adv_filter.py`](scripts/adv_filter.py) to call Apollo's People Search + email-finder API against `adv_icp_matches_us.csv`.
- A secondary email-verification pass (NeverBounce/ZeroBounce) is still worth adding regardless of vendor, to protect the <2% bounce guardrail agreed under prerequisite C2.
