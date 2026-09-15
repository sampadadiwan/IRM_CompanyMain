# Generating Account Entries for Multiple Fee Types with One Formula

**GenerateAccountEntryMultiple** is a rule type that lets one formula generate account entries for several fee types at once. Instead of maintaining one formula per fee type per period (Quarterly, YTD, Since Inception), you list all the fee types inside a single formula — the system still creates a separate account entry for each fee type on each commitment, exactly as if you had written them individually.

> **Where to find it:** Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Account Entries → Allocation Formulas**; create with **New Fund Formula** and choose **GenerateAccountEntryMultiple** as the Rule Type. Creating formulas is limited to CapHive support users; editing needs update rights on the fund.

This guide is for fund administrators who maintain allocation formulas.

---

## Before and After

A typical reporting setup needs Quarterly, YTD, and Since Inception entries for each of five fee types — 15 formulas. With this rule type, that becomes 3:

| Name | Rule Type | Formula |
|---|---|---|
| Quarterly Reporting | GenerateAccountEntryMultiple | `capital_commitment.quarterly(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |
| YTD Reporting | GenerateAccountEntryMultiple | `capital_commitment.year_to_date(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |
| Since Inception Reporting | GenerateAccountEntryMultiple | `capital_commitment.since_inception(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |

The result is unchanged: every commitment still gets its own "Quarterly Management Fees", "Quarterly Custody Fees", etc. entry with the correct amount, plus a fund-level total per name (and, when **Roll Up** is ticked, a cumulative entry per name per commitment) — the same entries as before, from far fewer formulas.

## Setting One Up

1. Open the fund, choose **Actions → Account Entries → Allocation Formulas** (the **Fund Formulas** page) and click **New Fund Formula**. This button is shown only to CapHive support users, so fund teams usually ask support to add the formula.
2. Choose **GenerateAccountEntryMultiple** as the Rule Type.
3. Write the formula as usual, but put the fee-type names in a **quoted, comma-separated list inside square brackets** where a single name would normally go.
4. Give the formula a descriptive batch name (e.g. "Quarterly Reporting") — the individual entries are **not** named after the formula; they are named after each fee type in the list.

## How Entries Are Named

Each generated entry is named *prefix + fee type*. The prefix comes automatically from the period used in the formula:

| Formula uses | Entries are named | Example |
|---|---|---|
| `quarterly` or `period` | Quarterly … | Quarterly Management Fees |
| `year_to_date` | YTD … | YTD Management Fees |
| `since_inception` | Since Inception … | Since Inception Management Fees |
| anything else | no prefix | Management Fees |

These are the same names the single-formula setup produced, so investor statements and templates that reference them keep working.

**Custom prefix**: add `name_prefix=My Prefix ` to the formula's meta data to override the automatic prefix. Include the trailing space — otherwise the prefix runs into the name (`My PrefixManagement Fees`).

## Things to Know

- **Same output, fewer formulas.** Per-commitment entries, fund-level totals, and per-entry explanations are all produced per fee type, just as with individual formulas. Cumulative per-commitment entries per name are created only when **Roll Up** is ticked.
- **The list must contain at least one quoted name.** The formula will not save otherwise.
- **Keep each entry name in only one formula** (for a given entry type). Totals are grouped by entry name, so two formulas generating the same name would sum into each other's totals — the same as it has always been for two single formulas sharing a name.
- **Duplicates in the list are ignored** — each fee type generates once.
- **The "Generate Additional Numbers" checkbox cannot be combined** with this rule type; write separate Quarterly / YTD / Since Inception formulas instead, as in the example above.
- **Re-running a period is safe.** Entries from the previous run for the same period are replaced, not duplicated.

## Bulk Actions on the Fund Formulas Page

The fund's **Fund Formulas** page (Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Account Entries → Allocation Formulas**) has a **Bulk Actions** dropdown for switching many formulas on or off in one step. It appears next to the **Enable All** dropdown **only after a filter is applied**: open **Enable All → Filter** (this adds a filter for the fund and shows the **Filter** card), add conditions such as Rule Type or Tag List if you want, and click the search icon. The table's own search box filters in the browser only and does not bring up the menu.

| Action (exact label) | What it does | Shown when |
|---|---|---|
| **Enable** | Sets each matching formula to enabled, so later allocation runs include it. | A filter is applied on a fund's Fund Formulas page |
| **Disable** | Sets each matching formula to disabled, so later allocation runs skip it. Entries it already generated stay. | A filter is applied on a fund's Fund Formulas page |

Each action asks you to confirm, then applies to **every formula matching the filter for that fund, including ones on other pages** (the table's search box does not narrow it). It runs in the background: the page shows "Bulk Action started, please check back in a few mins.", you get an in-app alert per formula and a final "Enable completed for N records" (or Disable) alert, and if any formula fails to save you also get an email listing each failed formula and its error. There is no undo — run the opposite action on the same filter. The **Enable All** / **Disable All** items in the **Enable All** dropdown are different: they switch every formula of the fund immediately, without a filter or background job. **Generate AI Descriptions** (top of the page) is a separate background job that writes an AI description for the fund's formulas that do not have one yet.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find a fund's formulas, where GenerateAccountEntryMultiple formulas live?**
Sidebar → [**Funds → Funds**](/funds), open the fund, then **Actions → Account Entries → Allocation Formulas**. This opens the fund's **Fund Formulas** page. The **Account Entries** sub-menu appears only when account entries are enabled for your entity.

**How do I find the GenerateAccountEntryMultiple formulas in a long list?**
On the **Fund Formulas** page, type GenerateAccountEntryMultiple in the table's search box to narrow the list. Each formula's page shows its rule type, formula and meta data.

**Where are the bulk actions for fund formulas?**
On the fund's **Fund Formulas** page, apply a filter (**Enable All → Filter**, then the search icon); a **Bulk Actions** dropdown with **Enable** and **Disable** then appears next to **Enable All**. See [Bulk Actions on the Fund Formulas Page](#bulk-actions-on-the-fund-formulas-page).

**Why don't I see the Bulk Actions button on the Fund Formulas page?**
The fund formula **Bulk Actions** dropdown is shown only when the page was opened from a fund and a filter is applied. Typing in the table's search box does not count, because it filters in the browser. Use **Enable All → Filter** and click the search icon, and the button appears.

**Where do I see the account entries these formulas generate?**
Fund page **Actions → Account Entries → Fund Account Entries** for the fund-level totals, or a commitment's **Account Entries** tab for folio entries. After an allocation run, the run's **Account Entries** icon under **Previous Runs** lists what that run generated.

### Creating, updating and managing these formulas

**How do I create a GenerateAccountEntryMultiple formula?**
On the **Fund Formulas** page click [**New Fund Formula**](/fund_formulas/new), choose **GenerateAccountEntryMultiple** as the **Rule Type**, set **Name**, **Sequence**, **Entry Type** and the **Formula** with the quoted names in square brackets, then **Save**. **New Fund Formula** is shown only to CapHive support users. See [Setting One Up](#setting-one-up).

**Who can create, edit or delete these formulas?**
Creating a formula (and **Upload**) is limited to CapHive support users, so fund teams usually ask support to add one. Editing, enabling/disabling and deleting need update rights on the fund (granted on the fund's **Access** tab) or the company admin role.

**How do I edit an existing formula, for example to add a fee type to the list?**
Click **Edit** on the formula's row or on its page, add the new quoted name inside the square brackets, and **Save**. The names take effect on the next allocation run.

**How do I delete or switch off a formula?**
Open the formula and click **Delete** (confirm), or use the dropdown on its page to **Disable** it. To switch off several, use the fund formula **Bulk Actions → Disable** after filtering, or **Enable All → Disable All** for every formula of the fund. A disabled formula is skipped by allocation runs.

**How do I enable or disable many fund formulas at once with bulk actions?**
On the fund's **Fund Formulas** page apply a filter that matches the formulas (**Enable All → Filter**, add conditions, click the search icon), then choose **Bulk Actions → Enable** or **Bulk Actions → Disable** and confirm. It runs in the background for every matching formula of that fund. To switch every formula of the fund without filtering, use **Enable All → Enable All** or **Disable All** instead.

**How do I run the formula?**
Formulas run as part of an allocation run: click **Run All** on the Fund Formulas page or use **Actions → Account Entries → Allocate Account Entries**, set the dates, tick **Run Allocation Formulas** and **Submit**. Allocation run templates can run it too.

**Can I import or export formulas in bulk?**
**Download** on the Fund Formulas page exports the list to Excel. **Upload** (a Fund Formula import) is shown only to support users.

**How do I set a custom name prefix?**
Put `name_prefix=My Prefix ` (with the trailing space) in the formula's **Meta Data** field and save. See [How Entries Are Named](#how-entries-are-named).

### Why use GenerateAccountEntryMultiple

**Why should I use GenerateAccountEntryMultiple?**
It collapses one-formula-per-fee-type-per-period into one formula per period. Five fee types across Quarterly, YTD and Since Inception go from 15 formulas to 3, with the same entries produced. See [Before and After](#before-and-after).

**What does it let me do more easily?**
Add or remove a fee type in one place for all folios, keep Quarterly, YTD and Since Inception lists identical, and review a shorter formula list and dependency diagram.

**What goes wrong if I keep separate single formulas instead?**
Nothing breaks, but every new fee type means adding several formulas, and it is easy to add it to Quarterly and forget YTD, leaving a statement line blank for one period type.

**Who typically uses it?**
Fund administrators and CapHive support staff who maintain a fund's allocation formulas, especially for reporting entries shown on investor statements.

### What happens when I …

**What happens when I save the formula?**
It is validated: the formula must parse and contain a non-empty list of quoted names, and **Generate Additional Numbers** must be unticked. Saving creates or updates the formula only; no account entries change until the next allocation run.

**What happens when an allocation run reaches this formula?**
For each commitment the formula is evaluated once per name in the list, creating one entry named prefix + fee type with the formula's entry type. A fund-level total is then created for each name, and, if **Roll Up** is ticked, a cumulative entry per name per commitment. Only the user who started the run gets in-app progress alerts.

**What happens when I re-run the same period?**
At the start of the run, entries this formula generated in that period are hard-deleted and then regenerated, so there are no duplicates. Locked allocation runs cannot be overwritten; unlock first.

**What happens when I remove a fee type from the list?**
The next run for a period deletes all this formula's entries in that period and regenerates only the names still listed, so that fee type's entries disappear for that period. Periods you do not re-run keep their old entries.

**What happens when I delete or disable the formula?**
Later runs no longer generate the names, but entries it already generated are not removed, even when you re-run the period: a run only clears entries of the enabled formulas it runs. Any later formula that reads one of those values shows as broken on the **Dependencies** page.

**What happens when I use Bulk Actions → Enable on the Fund Formulas page?**
After you confirm, a background bulk job saves each fund formula matching the filter as enabled, so the next allocation run includes it; no account entries change until then. You get an in-app alert per formula and a final "Enable completed for N records" alert, plus an email listing any formula that failed validation. There is no undo; run **Bulk Actions → Disable** on the same filter.

**What happens when I use Bulk Actions → Disable on the Fund Formulas page?**
After you confirm, a background bulk job saves each matching fund formula as disabled, so later allocation runs skip it; entries it already generated are not removed. Later formulas reading its values show as broken on the **Dependencies** page. You get per-formula alerts, a final "Disable completed for N records" alert and an email for any failures. Undo with **Bulk Actions → Enable** on the same filter.

**Can I undo a change?**
There is no undo. Edit the formula back to its previous text and re-run the affected periods to regenerate the entries.

### Troubleshooting and edge cases

**The formula will not save: "must contain a non-empty array of quoted account entry names". Why?**
The list is missing, empty, or contains something other than plain quoted strings (for example a variable). Write the names as `["Management Fees", "Audit Fees"]` directly in the formula.

**The formula will not save because of Generate Additional Numbers. Why?**
**Generate Additional Numbers** (the YTD/Quarterly auto-generation checkbox) cannot be combined with this rule type, because it would name entries after the batch name. Untick it and create separate Quarterly, YTD and Since Inception formulas.

**My entries came out without the Quarterly prefix. Why?**
The prefix is derived from the method that receives the names list: `quarterly` (or its alias `period`), `year_to_date` or `since_inception`. Any other method gives no prefix; add `name_prefix=` in **Meta Data** to set one.

**My entry names run together, like "My PrefixManagement Fees". Why?**
The `name_prefix` in **Meta Data** has no trailing space. Change it to `name_prefix=My Prefix ` and re-run the period.

**Two formulas generate the same entry name. What happens?**
Totals are grouped by entry name, so their amounts sum into each other's totals. Keep each entry name (for a given entry type) in only one formula.

**I listed the same fee type twice. Do I get two entries?**
No. Duplicates in the list are ignored and each fee type is generated once.

**Can a later formula read one of these generated values?**
Yes. Refer to the prefixed name as a variable, for example `@quarterly_management_fees`, and make sure that formula has a higher sequence. The **Dependencies** page shows each name as a separate value.

**A fund formula bulk action finished but some formulas did not change — why?**
Bulk **Enable** and **Disable** save each formula with its normal validations, so a formula whose text no longer passes validation (for example a syntax error or an empty names list) is not saved. The final alert says how many errors there were, and the email lists each failed formula with its error; fix the formula and run the bulk action again.

**Does a bulk action on fund formulas apply to rows on other pages?**
Yes. Fund formula **Bulk Actions** apply to every formula of that fund matching the applied filter, including rows on other pages. Text typed into the table's search box is ignored, so check the filter conditions, not just the visible rows, before confirming.

**Will investor statement templates still find the entries?**
Yes, provided the prefixed names match the names your single formulas produced (for example "Quarterly Management Fees"), because the automatic prefixes are the same.

## Related Guides

- [Formula Dependencies](formula_dependencies_user_guide) — checking that later formulas can read the values this formula generates.
- [Allocation Run Templates](allocation_run_templates_user_guide) — running the formulas for a period, fund by fund in order.
- [Account Entries Period Report](account_entries_period_report_user_guide) — reviewing the entries a run produced.
- [Capital Commitments](capital_commitments_user_guide) — the folios each entry is generated for.
