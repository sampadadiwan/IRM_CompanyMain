# New Agent Ideas — For Fund Managers and Investors

A set of proposed additions to the CapHive agent lineup. Grouped by who benefits:
fund managers (GPs) running the fund, and investors (LPs) who committed capital to it.
None of these are built yet — this is a proposal to prioritize from.

---

## For Fund Managers

### Fee & Carry Checker - Yes, Clarify
- Recalculates management fees and carried interest from the fund's actual transaction
  records and compares the result to what was charged.
- Flags any mismatch before it reaches an LP statement or an auditor's desk.
- Value: catches fee and carry errors early, when they're a quick fix — not during an
  audit, when they're a credibility problem.

### Capital Call Forecaster - No
- Looks ahead at the fund's spending pace and pipeline commitments to estimate when the
  next capital call will be needed and roughly how large it will be.
- Gives the fund manager a heads-up instead of a scramble.
- Value: more time to plan a call, and a smoother experience for LPs who get earlier notice.

### Investor Concentration Watchdog - No
- Continuously checks the fund's investor base for risk signals: one investor holding
  too large a share of the fund, capital that's been sitting uncalled too long,
  commitment periods approaching their end date.
- Value: surfaces concentration and timing risk before it becomes a fundraising or
  liquidity problem, not after.

### Valuation Consistency Checker - No
- Compares each portfolio company's recorded valuation against its most recent funding
  round or comparable company pricing.
- Flags marks that look stale or inconsistent with the rest of the portfolio.
- Value: stronger, more defensible valuations going into LP reporting and audits.

### Deal Closing Checklist - Yes
- Before a deal is marked "Closed," confirms every required item is actually in
  place — signed agreements, reconciled ownership records, completed diligence items.
- Value: prevents deals from closing with loose ends that surface later as disputes
  or cleanup work.

### Investment Candidate Shortlister - Yes
- Given a folder of materials on a prospective investment — pitch decks, financial
  models, spreadsheets, data room PDFs — plus the fund's stated investment thesis
  (sector focus, stage, check size, must-have criteria), reviews everything and scores
  how well the candidate matches.
- Supplements the uploaded materials with outside research: recent news, market
  sizing, competitive landscape, and founder or leadership background.
- Across a batch of candidates, produces a ranked shortlist — each with a fit score, a
  plain-language rationale, and a list of open questions or gaps to chase down before
  committing time to deeper diligence.
- Value: compresses the first-pass screening step — today done manually and
  inconsistently, deal by deal — into a fast, consistent first cut. Frees the
  investment team's time for the candidates that actually clear the bar, instead of
  spending it working out which ones do.

### LP Letter Drafting Assistant
- Pulls together a first draft of the quarterly investor letter — fund performance,
  portfolio company highlights, notable events — ready for the fund manager to review
  and edit.
- Value: cuts the time spent assembling quarterly updates from scratch each cycle.

### Audit Readiness Sweep - Yes
- Ahead of year-end audit, checks that required documents are present and properly
  dated: tax forms, board minutes, financial statements.
- Value: turns audit prep from a fire drill into a routine check, run well before the
  auditor asks.

### Portfolio Company News & Market Watch - Yes
- Continuously pulls outside information about a portfolio company — news mentions,
  funding and M&A activity, leadership changes, litigation, and financial or market
  data from paid data providers — and summarizes what's new and relevant.
- Attaches findings directly to the portfolio company record so the fund manager has
  external context sitting alongside internal KPI and valuation data, not scattered
  across separate subscriptions and searches.
- Can also flag anything that looks like a red flag (e.g. a lawsuit, a leadership
  departure, a down round at a comparable company) so it doesn't get missed between
  quarterly check-ins.
- Value: fund managers currently piece this together manually across several paid
  subscriptions and ad-hoc searching; this collapses it into one recurring check per
  company and catches early warning signs sooner. Doubles as ready-made source
  material for board briefings and the quarterly LP letter.
- Note: this one has an ongoing cost, since it depends on paid outside data sources
  rather than data already inside CapHive — worth scoping which sources (news,
  financial data, legal/litigation records) actually justify the subscription cost
  before committing.

---

## For Investors (LPs)

Today, investors can only ask CapHive's assistant questions about their own fund data.
Everything below adds the other half: CapHive proactively reaching out to keep
investors informed, instead of only answering when asked.

### Investor Portfolio Digest
- A periodic email to each investor summarizing what's changed since their last
  update: performance, new portfolio companies, upcoming capital calls or distributions.
- Value: investors stay current without having to log in and dig for it, and fund
  managers field fewer "what's new" emails.

### Capital Call & Distribution Explainer - No
- When an investor receives a capital call or distribution notice, they can ask
  "why is this amount what it is?" and get a clear breakdown — how much is fees,
  how much is the actual investment, how it maps to their ownership share.
- Value: fewer confused emails to the fund manager's team; investors get an answer
  immediately instead of waiting on a reply.

### Document Concierge - No
- Investors can ask directly for a specific document — "my Q2 capital account
  statement," "my latest K-1" — and get it right away instead of searching the
  portal.
- Value: less time spent by both sides locating paperwork.

### Tax Document Reminder
- Proactively lets investors know when a new tax document (like a K-1) has been
  published, or nudges them if one they're expecting is running late relative to
  filing deadlines.
- Value: fewer missed tax deadlines, fewer "where's my K-1" support requests during
  tax season.

### Co-Investment Opportunity Matcher - No
- With the investor's permission, flags new deal opportunities that match their
  stated interests (sector, check size) as the fund manager's pipeline develops.
- Value: a genuinely new offering — turns the investor relationship into a two-way
  channel and can be a differentiator when competing for investor capital.

---

## Not Ready Yet

**Peer/Benchmark Comparison** — investors asking "how does this fund's performance
compare to similar funds of the same vintage" is a natural question, but answering it
requires outside benchmark data CapHive doesn't currently have access to. Worth
revisiting once a data source is identified.

---

## Suggested Starting Point

Of the list above, two stand out as the best combination of impact and how closely
they follow the pattern of agents CapHive has already built successfully:

- **Fee & Carry Checker** — same shape as the existing nightly data-quality checks,
  just aimed at fee and carry accuracy specifically.
- **Investor Portfolio Digest** — same shape as the existing cash flow reporting agent,
  redirected at investors instead of fund managers.

Recommend starting there, then expanding into the higher-effort items like the
Co-Investment Matcher once the pattern is proven.
