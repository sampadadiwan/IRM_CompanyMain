# Ratio Run Templates User Guide

Ratio Run Templates let you save a set of filter parameters once and re-run the same calculation for any date with a single click — individually, all at once, or grouped by tag.

> For background on how cross-fund and cross-portfolio ratios are computed and what a FundRatioRun record contains, see the **[Fund Ratios User Guide](fund_ratios_user_guide)**.

---

## Table of Contents

1. [What Is a Ratio Run Template?](#what-is-a-ratio-run-template)
2. [Creating a Template](#creating-a-template)
3. [Run Types — Cross-Fund vs Cross-Portfolio](#run-types)
4. [Tags and Bulk Triggering](#tags-and-bulk-triggering)
5. [Triggering a Single Template](#triggering-a-single-template)
6. [Trigger All](#trigger-all)
7. [Trigger by Tag](#trigger-by-tag)
8. [Viewing Past Runs](#viewing-past-runs)
9. [Idempotency — Re-running the Same Date](#idempotency)
10. [Frequently Asked Questions](#frequently-asked-questions)

---

## What Is a Ratio Run Template?

A template stores the filter inputs for a cross-fund or cross-portfolio ratio calculation:

- Which **source funds** to include
- Which **portfolio companies** to include (explicit selection, tags, or sector filter)
- An optional **anchor fund** used for document storage
- A **display name** and optional **tags** for grouping

When you trigger a template you supply only the **end date**. Everything else comes from the saved configuration. The system then enqueues a `FundRatiosScenarioJob` and creates (or reuses) a `FundRatioRun` linked to the resulting ratios.

---

## Creating a Template

1. Go to **Funds → Ratio Templates** in the sidebar.
2. Click **New Template**.
3. Fill in:
   - **Name** — must be unique within your entity.
   - **Tags** — optional grouping labels (Select2, free-text or existing tags). Multiple tags allowed.
   - **Anchor Fund** — the fund used for document storage. Leave blank for cross-portfolio runs that span all funds.
   - **Source Funds** — the funds whose data feeds the calculation. Leave blank to include all entity funds.
   - **Portfolio Companies / Tags / Sectors** — leave all blank for a cross-fund run; fill any one (or more) for a cross-portfolio run. When both **Portfolio Company Tags** and **Sectors** are set, only companies that match **both** filters are included (AND logic). Setting only one of the two keeps all companies that match that filter.
   - **Display Order** — controls the order templates appear in the index.
4. Click **Save**. The **run type** (cross-fund or cross-portfolio) is inferred automatically from the filter fields — you do not set it manually.

---

## Run Types {#run-types}

| Run Type | When it applies |
|---|---|
| **Cross-fund** | Source funds selected, no portfolio company filters |
| **Cross-portfolio** | Any portfolio company filter set (explicit IDs, tags, or sectors) |

The run type is re-inferred every time you save the template, so changing the filters automatically updates the type.

---

## Tags and Bulk Triggering

Tags are free-text labels you assign to group templates together. For example, tagging several templates `monthly` lets you trigger all of them in one action for a given end date.

- A template can have **multiple tags**.
- Tags are shared across your entity — typing in the Tags field shows existing tags as suggestions.
- Tags have no effect on the calculation itself; they are purely for organisation and bulk triggering.

---

## Triggering a Single Template

From the index table, click the **Run** button (or open the Actions dropdown → Run) next to the template you want to trigger, enter an end date, and submit. The job runs in the background and you will receive a notification when it completes.

---

## Trigger All

The **Run All** panel (collapsed by default at the top of the index) lets you trigger every template for the entity in a single action. Enter an end date and click **Run All Templates**.

Each template produces its own `FundRatioRun` identified by its filter fingerprint. Two templates with identical filter inputs will share a single run record (see [Idempotency](#idempotency)).

---

## Trigger by Tag

The **Run by Tag** panel lets you trigger only templates that carry a specific tag. Enter a tag and an end date, then click **Run by Tag**.

Useful when you have templates organised by frequency (e.g. `monthly`, `quarterly`) and want to run only the relevant group on the reporting date.

---

## Viewing Past Runs

Click **Actions → View Runs** on any template row to see all historical `FundRatioRun` records produced by that template, ordered by end date descending. From there you can navigate to the run detail page which shows the exact inputs and links to the generated ratios.

---

## Idempotency — Re-running the Same Date {#idempotency}

Triggering the same template twice for the same end date does **not** create duplicate data. The system computes a SHA-256 fingerprint from the filter inputs and uses it as the run's unique identifier. If a run with that fingerprint already exists for that date, the existing record is reused and the ratios are recalculated in place.

This means you can safely re-trigger a template to refresh ratios after updating valuations or cash flows without worrying about duplicates.

---

## Frequently Asked Questions

**Do I need to set an anchor fund?**
No. The anchor fund is used only for document storage (cash flow documents). If you leave it blank, the system picks the entity's first fund as a fallback for that purpose. The calculation itself is unaffected.

**What happens if I change a template's filters?**
Saved templates are independent snapshots. Changing a template's filters changes the fingerprint, so future triggers produce a new `FundRatioRun`. Existing runs are not affected.

**Can I delete a template?**
Yes. Deleting a template does not delete the `FundRatioRun` records or `FundRatio` rows it produced — those remain and can still be viewed through the fund ratios index.

**The run type shows "cross-fund" but I expected "cross-portfolio". Why?**
The run type is inferred: unless at least one portfolio company filter (explicit IDs, tags, or sectors) is set, the template is treated as cross-fund. Add a portfolio company tag or sector filter to switch it to cross-portfolio.

**What happens when both Portfolio Company Tags and Sectors are set?**
The two filters are intersected — only companies that satisfy **both** conditions are included. For example, if Tags = `growth` and Sectors = `Ecommerce`, only companies tagged `growth` **and** in the `Ecommerce` sector appear in the calculation. Companies that have the tag but belong to a different sector (or vice versa) are excluded. If you want a broader union, create two separate templates — one per filter — and trigger both for the same date.

**What if I set explicit Portfolio Companies alongside Tags and Sectors?**
Explicitly selected companies are always included regardless of the tag/sector filters. The AND intersection applies only to companies resolved through the tag and sector fields.
