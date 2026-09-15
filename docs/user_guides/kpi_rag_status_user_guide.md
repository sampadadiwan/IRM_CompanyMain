# RAG Status User Guide

RAG status is a red/amber/green flag CapHive can show next to a KPI value, so you and your team
can spot at a glance which numbers are on track and which need attention — without doing the
comparison yourself every time a report comes in.

> **Where to find it:** Sidebar → [**Stakeholders → View Stakeholders**](/investors) → open a portfolio company → **Kpi Mapping** tab → **Edit** on the KPI's row → expand **RAG Rule (Red / Amber / Green)**. Needs the *Enable Kpis* permission on your user plus edit rights on the mapping (company_admin, or an employee with update access).

## 📑 Table of Contents
1. [What RAG Status Does](#what-rag-status-does)
2. [Setting Up a RAG Rule](#setting-up-a-rag-rule)
3. [How It's Calculated](#how-its-calculated)
4. [Worked Examples](#worked-examples)
5. [Where You'll See It](#where-youll-see-it)
6. [Things to Know](#things-to-know)
7. [Frequently Asked Questions](#frequently-asked-questions)

---

## What RAG Status Does

For any KPI you track, you can tell CapHive what "good," "borderline," and "concerning" look
like. Once that's set up, CapHive checks every new value against your rule automatically — the
moment a number is approved — and shows a colored flag:

*   🔴 **Red** — outside the acceptable range, worth a look.
*   🟡 **Amber** — in between; not a problem yet, but trending the wrong way.
*   🟢 **Green** — on track.

You set this up once per KPI. From then on, every newly approved or changed value for that KPI
is flagged automatically — no one has to re-check it by hand. Values that were already approved
before you set up the rule are flagged when you click **Recompute RAG Status** on the mapping.

---

## Setting Up a RAG Rule

Go to the KPI mapping for the KPI you want to flag (Portfolio Company → **Kpi Mapping** tab →
**Edit** on the KPI's row) and expand the collapsible **RAG Rule (Red / Amber / Green)** section.
You'll see four RAG fields:

*   **RAG comparator tag** — what should the reported value be measured against? Choose
    **Prior period** to compare a value against this same KPI's own most recently reported
    period — no separate upload needed, since that value is typically already sitting in CapHive.
    Otherwise, pick (or type) the tag your fund uses for the comparison report — most commonly
    **Budget**, but it can be anything your reports are tagged with (for example, a "PriorYear"
    tag to compare against last year's figure, when that's a genuinely separate report rather
    than simply "whatever was reported before this one"). Leave this **blank** if the KPI doesn't
    need a comparison at all — some KPIs (a margin percentage, a ratio, a number of months of
    runway) are judged on their own, with nothing to divide against.
*   **RAG direction** — is a higher number better, or a lower number better? Revenue and profit
    margins are "higher is better." Customer churn and cash burn are "lower is better."
*   **RAG red threshold** — the cutoff below which (or above which, for "lower is better" KPIs)
    a value is flagged red.
*   **RAG green threshold** — the cutoff at or above which (or at/below which, for "lower is
    better" KPIs) a value is flagged green. Anything between red and green is amber.

Direction, red threshold and green threshold must be set together (or all left blank), and the
two thresholds can't be equal — for "higher is better" red must be below green, for "lower is
better" above it. Click **Save**. Once saved, the screen shows your rule back to you in
plain language, e.g. *"Red below 70% of Budget · Green at or above 90%"* — so you can always
confirm what's configured without having to remember the raw numbers.

---

## How It's Calculated

There are two ways a RAG rule can work, depending on whether you filled in a comparator tag:

**With a comparator tag** — the reported value is divided by the matching value from the
comparison report (e.g. this month's Actual ÷ this month's Budget), and that ratio is what gets
checked against your red/green thresholds. A threshold of "0.7" here means "70% of the
comparator."

**With Prior period** — works the same way, except the value it divides by is whichever report
for this same KPI most recently came before the one being checked, however far back that
actually is. It's not a fixed "one month ago" or "one year ago" — it's simply the last time this
KPI was reported before now, so it lines up naturally whether you report monthly, quarterly, or
on some other cadence.

**Without a comparator tag (blank)** — the reported value is checked directly against your
thresholds, with nothing to divide by. This is the right choice for a KPI that's already a
self-contained number, like a percentage or a ratio.

A tagged comparator must be an approved report with exactly the same **As Of** date and exactly
the same tag. If the comparator value is exactly zero, the KPI is flagged **Red** (the Workbook
check instead skips RAG for a zero comparator).

If the comparison value (whether a tagged report like Budget, or the prior period) hasn't been
entered yet, the KPI simply has no RAG status yet — it isn't guessed at. As soon as the
comparison value is entered, the flag appears automatically, even on values that were reported
earlier. This also means: if you enter periods out of order (say, this month before catching up
on a missed earlier one), the earlier value's arrival will retroactively flag the later one.

---

## Worked Examples

| KPI | Comparator tag | Direction | Red threshold | Green threshold | What it means |
|---|---|---|---|---|---|
| Revenue | Budget | Higher is better | 0.7 | 0.9 | Red if actual revenue is below 70% of budget; green at 90% or above. |
| Net Burn | Budget | Lower is better | 1.2 | 1.0 | Red if spending is more than 120% of the budgeted burn; green at or under budget. |
| Gross Margin % | *(blank)* | Higher is better | 0.40 | 0.55 | Red if margin is below 40%; green at 55% or above — judged directly, no comparator needed. |
| Cash Runway (months) | *(blank)* | Higher is better | 6 | 12 | Red under 6 months of runway; green at 12 months or more. |
| Customer Churn % | Budget | Lower is better | 1.5 | 1.0 | Red if churn is more than 1.5× the budgeted rate. |
| Revenue Growth YoY | PriorYear | Higher is better | 1.10 | 1.20 | Red if this year is below 110% of last year's figure (under 10% growth), compared against a separately uploaded prior-year report. |
| Revenue (month-on-month) | Prior period | Higher is better | 0.95 | 1.00 | Red if this month's revenue is below 95% of last month's — compared automatically against whatever was reported last, no extra upload needed. |
| Leverage Ratio (debt covenant) | *(blank)* | Lower is better | 4.0 | 3.6 | Red if leverage exceeds the 4.0x covenant limit; green comfortably under it. |

---

## Where You'll See It

*   **The Kpi Mapping tab** — the configured rule, in plain language, on both the mappings
    list and the mapping's **Show** page.
*   **The KPI reporting grid** — a small colored badge next to any value that has a RAG status.
*   **A KPI's own detail page** — the value itself is shown in a colored badge (red/amber/green),
    with a one-line note underneath naming the rule that produced it (e.g. *"Amber — Red below
    70% of Budget · Green at or above 90%"*), so you never have to go find the rule separately to
    understand why a value is flagged.
*   **The Workbook check panel**, when a portfolio company uploads a file — a red or amber note
    calling out any value that falls in your red or amber band, right alongside the other checks
    described in the [KPI Management & Workbook Upload User Guide](kpi_upload_user_guide). The
    Workbook check applies RAG only to workbooks tagged *Actual*.

---

## Things to Know

*   RAG status updates automatically whenever an approved value or its comparison value changes.
    Adding or changing a rule on a mapping does **not** re-evaluate KPIs already approved — click
    **Recompute RAG Status** on the mapping's **Show** page for that. Removing a rule does not clear
    flags already stored (not even with Recompute), so treat older flags on that KPI as stale.
*   A KPI with no RAG rule configured, or one still waiting on its comparison value, simply shows
    no flag rather than a misleading one.
*   RAG status is separate from the plausibility warnings (like "this looks 1,000× off") described
    in the workbook upload guide — RAG tells you whether a value is *good*, plausibility checks
    tell you whether a value was probably *entered correctly*.
*   **Prior period** only ever compares like against like — a monthly report against the
    previous monthly report, a quarterly report against the previous quarterly report, and so on
    (never a month against a quarter). It also compares against the prior report with the same tag
    as the KPI's own report — an Actual against a prior Actual, a Budget against a prior Budget.
*   **RAG rules only apply to approved figures.** A value still awaiting your approval is never
    flagged itself, and is never used as the comparator for judging another value — a number
    nobody has confirmed yet shouldn't drive a flag someone might act on. Once you approve a
    figure, any flag it's involved in appears (or updates) automatically — you don't need to
    re-enter anything.
*   RAG rules can't be set in bulk (the KPI mapping **Upload** file has no RAG columns), and a KPI's
    status can't be set by hand — the **Rag status** drop-down on a KPI's edit form is not saved.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I set up a RAG rule in CapHive?**
Sidebar → [**Stakeholders → View Stakeholders**](/investors), open the stakeholder whose **Category** is *Portfolio Company*, click the **Kpi Mapping** tab, then **Edit** on the KPI's row. Expand **RAG Rule (Red / Amber / Green)** to see the four RAG fields. See [Setting Up a RAG Rule](#setting-up-a-rag-rule).

**Where do I see the rule that is configured for a KPI?**
The **Kpi Mapping** tab lists each mapping with its rule in plain language (or "Not configured"), and **Show** on a row displays it too. On the edit form, **Current rule:** appears under the fields once a rule is saved.

**Where do I see the red/amber/green flags?**
In the KPI grid (the stakeholder's **Kpis** tab, or **Grid View** on the [**KPI Reports**](/kpi_reports) list) as a small badge above the value, on a KPI's own page under **RAG Status** with the rule underneath, and in the **Workbook check** panel when an Actual workbook is uploaded. See [Where You'll See It](#where-youll-see-it).

**I can't see the Kpi Mapping tab.**
It only appears on stakeholders whose **Category** is *Portfolio Company*, and only if your user has the *Enable Kpis* permission. A company admin can switch that on at Company menu (house icon, top right) → [**User**](/users) → edit the user.

**Who can set up or change RAG rules?**
Anyone who can edit the KPI mapping: a *company_admin* of the fund, or an employee who has update access to that record, with *Enable Kpis* switched on. Users who can only view mappings see the rule but no **Edit** or **Recompute RAG Status** button.

### Creating, updating and managing RAG rules

**How do I create a RAG rule?**
Edit the KPI mapping, expand **RAG Rule (Red / Amber / Green)**, choose the **RAG comparator tag** (a tag such as *Budget*, *Prior period (this KPI's own last report)*, *Other* to type a tag, or *None — judge the value directly*), pick the **RAG direction**, enter **RAG red threshold** and **RAG green threshold**, and click **Save**.

**Which values do I enter as thresholds?**
With a comparator, thresholds are ratios of the comparator: `0.7` means 70% of Budget or of the prior period. With *None*, they are the raw KPI value (e.g. `6` months of runway, `0.40` for a 40% margin stored as a fraction). See [Worked Examples](#worked-examples).

**How do I change an existing RAG rule?**
Edit the mapping, change the comparator, direction or thresholds, click **Save**, then open the mapping (**Show**) and click **Recompute RAG Status** so already-approved KPIs are re-flagged under the new rule.

**How do I remove a RAG rule?**
Edit the mapping, clear **RAG direction** and both thresholds together (they must be all set or all blank) and save. Flags already stored on approved KPIs are not cleared by this or by **Recompute RAG Status**, so treat older flags on that KPI as stale.

**Can I set RAG rules in bulk?**
No. The KPI mapping **Upload** file has no RAG columns, so RAG rules are set one mapping at a time on the edit form. **Download** on the **Kpi Mapping** tab exports the mappings list to Excel.

**Can I set a KPI's RAG status by hand?**
No. The status is only ever calculated from the mapping's rule. The **Rag status** drop-down on a KPI's edit form is not saved.

### Why use RAG status

**Why should I use RAG status?**
It turns every approved KPI into an instant on-track / borderline / concerning signal, so the portfolio team can scan dozens of companies and spot problems without dividing Actual by Budget in a spreadsheet every period.

**What does RAG status let me do?**
Judge a KPI against Budget, against any other tagged report (e.g. *PriorYear*), against its own last reported period, or against absolute limits such as a debt covenant, with a direction that knows whether higher or lower is better, and see the reason for each flag next to the value.

**What happens if I don't set up any RAG rules?**
KPIs simply show no flag. Nothing else changes: uploads, approvals, charts and dashboards work as before, and the Workbook check shows no RAG notes.

**Who typically uses RAG status?**
Portfolio-monitoring and fund operations staff set the rules per KPI; partners, IC members and portfolio managers read the flags in the KPI grid and on KPI pages.

### What happens when I …

**What happens when I save a RAG rule?**
The rule is stored on the KPI mapping and applies to that portfolio company's KPI from then on. Existing approved KPIs are not re-evaluated automatically; click **Recompute RAG Status** to flag them. No one is notified.

**What happens when I click Recompute RAG Status?**
After you confirm, a background job re-evaluates every approved KPI under that mapping and stores the new red/amber/green status (or none if the comparator is missing). When it finishes, you get an on-screen alert "Recomputed RAG status for N KPI(s)…"; no email is sent.

**What happens when a KPI is approved or its value changes?**
Its RAG status is recalculated immediately, and so are the KPIs that use it as a comparator (the Actual for the same date when a Budget is approved, and the next period when the prior period changes). Unapproved values never get a flag and are never used as a comparator.

**What happens if the comparator value is missing or zero?**
If no approved comparator exists yet (no Budget for that exact date, or no earlier period), the KPI has no flag. If the comparator is exactly zero, the KPI is flagged **Red**. See [How It's Calculated](#how-its-calculated).

**What happens when a KPI is unapproved?**
Its RAG status is cleared, and KPIs that relied on it as their comparator are re-evaluated (usually losing their flag until a comparator is approved again).

**What happens to RAG notes in the Workbook check?**
When a workbook tagged *Actual* is checked, values that fall in the red or amber band against an approved comparator are listed as notes. They are informational: they do not block **Submit Report** or saving. See the [KPI Management & Workbook Upload User Guide](kpi_upload_user_guide).

### Troubleshooting and edge cases

**The form says "RAG direction, red threshold and green threshold must all be set together".**
Fill in all three or leave all three blank. The comparator tag is optional (blank means judge the value directly).

**The form says the red threshold "must be below the green threshold".**
For *Higher Is Better* the red threshold must be lower than green; for *Lower Is Better* it must be higher. The two thresholds can never be equal.

**I saved a rule but no flags appear.**
Existing KPIs are only flagged after **Recompute RAG Status** or when a KPI is next approved or changed. Also check the KPIs are approved, and that an approved comparator exists for the same date (tag comparator) or an earlier period of the same type and tag (Prior period).

**My Budget comparison never flags anything.**
The Budget report must have the same **As Of** date and exactly the same tag as chosen in **RAG comparator tag**, and its values must be approved. A Budget dated 30 June does not match an Actual dated 31 May.

**Why is a KPI red when the actual looks fine?**
Check the comparator: a comparator of exactly zero always flags red, and a ratio threshold such as `0.9` entered for a *None* comparator is compared against the raw value, not a percentage of Budget.

**Does Prior period compare a month against a quarter?**
No. It uses the most recent earlier approved report with the same period type (Month with Month, Quarter with Quarter) and the same tag, however far back that is.

**Can I delete a KPI mapping that has a RAG rule?**
Not while KPIs reported under it still exist: the mapping is linked to those KPIs, so the delete fails. Remove the rule instead if you no longer want flags.

**Are RAG flags the same as the plausibility warnings in the Workbook check?**
No. RAG says whether a value is *good* against your rule; plausibility checks (like "this looks 1,000× off") say whether it was probably *entered correctly*. See [Things to Know](#things-to-know).

## Related Guides

- [KPI Management & Workbook Upload](kpi_upload_user_guide) — how KPIs are uploaded, staged and approved before RAG applies.
- [KPI Parent-Child Mapping](kpi_parent_child_mapping_user_guide) — the Kpi Mapping records that hold the RAG rule.
- [KPI Flexible Charts](kpi_flexible_charts_user_guide) — chart the KPIs you are flagging.
- [Dashboard Widgets](dashboard_widgets_user_guide) — show the Kpis grid with its badges on the Portfolio Company Dashboard.
- [Stakeholders (Investors)](investors_user_guide) — portfolio company stakeholders and their Kpis / Kpi Mapping tabs.
- [Portfolio Company Agent](agents/portfolio_company_agent_user_guide) — monitors whether KPIs are submitted on time.
