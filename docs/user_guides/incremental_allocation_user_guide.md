# Incremental Allocation and Suggested Run Checks

Support can switch a fund to incremental allocation, which stores each Since Inception total and carries it forward instead of adding up the fund's whole history on every run. The same menu builds the pre-run and post-run checks that confirm the switch worked.

> **Where to find it:** Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Account Entries → Allocation Formulas** → **Actions** → **Incremental allocation** or **Suggest run checks**. Both items are shown only to support users.

This guide is for support staff who set up and maintain a fund's allocation formulas.

---

## Why incremental allocation

Every allocation run copies the fund's account entries into a working file before it calculates. A formula that adds up a total "since inception" needs every entry back to the first one, so the copy grows with the fund's history even when the run is for one month. On a large fund most of the run's time is that copy.

An incremental fund reads the total a previous run stored and adds only the movement since then. The working file then only needs the current financial year, which makes the copy and the run much faster. The numbers are the same.

Two kinds of formula change when a fund is switched:

| Change | Why |
| --- | --- |
| Formulas that add up several Since Inception totals are combined into one that carries its own stored total forward | Each separate total would look for a stored figure that is never saved |
| Tracking formulas stop re-adding all history on top of their stored value | Otherwise the stored total grows with every run, not with the data |

Every changed formula gets a description of what it calculates, how, and why it was changed.

## The incremental allocation page

**Actions → Incremental allocation** on the fund's formulas page shows:

- **Status:** whether the fund is on incremental allocation.
- **Recommended steps:** each step is marked **Done** when the fund's own data shows it, and the next one is marked **Next**.
  1. Add run checks, including "Since Inception totals match history"
  2. Re-run the latest period before switching
  3. Preview and apply the switch
  4. Re-run the latest period after switching
- **Actions:** **Preview switching to incremental** for a fund that is not switched on. For one that is, **Preview switching off** and **Preview recomputing starting values**, with an optional date.
- **History:** every switch-on, switch-off and recompute, with who requested and applied it, when, and its status.

### Preview, then apply

Nothing is changed by a preview. It runs in the background and the page refreshes itself until it is ready. It shows:

- each formula change, with the formula now and after, and the description it will get
- anything that **blocks** the switch, with a link to the formula
- warnings, such as a tracking formula that has never produced a figure
- each tracking starting value, as stored now and recomputed

**Apply** is offered only on a finished preview with no blockers. Before writing anything, apply plans the change again. It writes nothing if:

- anything differs from the preview
- an allocation run on the fund has not finished
- an allocation run group is using the fund
- another preview or apply is in progress on the fund

The formula changes, starting values and the fund's switch are written together, or not at all.

| Status | Meaning |
| --- | --- |
| **Previewing** / **Applying** | Still running; the page refreshes itself |
| **Previewed** | Ready; **Apply** is offered |
| **Blocked** | Cannot be applied: something blocks it, or there is nothing to change |
| **Applied** | Written |
| **Refused** | Apply wrote nothing; the reason is shown and **Preview again** is offered |
| **Failed** | An error stopped it; the error is shown |

## Suggested run checks

**Actions → Suggest run checks** proposes the fund's pre-run and post-run checks. A pre-run check fails the run before anything is deleted; a post-run check fails it after its entries are written. Suggestions come from fixed rules that read:

- the fund's formulas
- the entity's custom fields
- the entry names and entry types the fund has uploaded

**Generate with AI** also asks AI for fund-specific checks the rules do not cover.

Each suggestion shows:

- **Rule** or **AI**, and the formulas and data behind it (under **Formula and evidence**)
- its result when tested against the fund's last successful allocation run: **Pass**, **Warn**, **Fail**, **Skipped** or **Not tested**. An AI suggestion written as free Ruby rather than a single helper call is **Not tested**: it is only evaluated once you add it, so read its text first
- a severity choice where the check allows one: **Fail (stops the run)** or **Warning**

Tick suggestions and choose **Add selected**, or **Download selected as xlsx** to import them later. A suggestion the fund already has is marked **Already present** and cannot be ticked.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I switch a fund to incremental allocation?**
Open the fund from [**Funds → Funds**](/funds), then **Actions → Account Entries → Allocation Formulas**. On the formulas page open **Actions** and choose **Incremental allocation**. The page shows the fund's status, the recommended steps, the preview buttons and the history.

**Where do I get suggested pre-run and post-run checks for a fund?**
On the fund's formulas page (fund **Actions → Account Entries → Allocation Formulas**), open **Actions** and choose **Suggest run checks**. If the fund already has a suggestion set, its most recent one opens; otherwise the page offers **Generate suggestions** and **Generate with AI**.

**Why don't I see Incremental allocation or Suggest run checks in the Actions menu?**
Both items are shown only to support users. Other users see the rest of the menu (**Enable All**, **Disable All**, **Filter**) as before. Opening either page directly without the support role shows "Access Denied".

**Where did the Enable All button go on the formulas page?**
It is now the **Actions** button. **Enable All**, **Disable All** and **Filter** are still its first items and work as before; support users also see **Incremental allocation** and **Suggest run checks** below them.

**How do I see who switched a fund to incremental allocation and when?**
Open **Actions → Incremental allocation** on the fund's formulas page. The **History** table lists every switch-on, switch-off and starting value recompute, with who requested it, who applied it, when, and its status. **Open** shows the preview it applied. Formula changes are also in the formula's audit trail.

### Creating, updating and managing incremental allocation

**How do I switch a fund to incremental allocation?**
On **Actions → Incremental allocation**, click **Preview switching to incremental** and wait for the preview. Check the formula changes and starting values, then click **Apply**. The page refreshes itself while each step runs and shows **Applied** when done.

**How do I switch a fund back off incremental allocation?**
On **Actions → Incremental allocation** for a switched-on fund, click **Preview switching off**, check which formulas will be restored, then **Apply**. Formulas that were combined get their earlier text and description back and the fund stops carrying totals forward. A description someone edited by hand after the switch-on is kept, and the preview says so. Tracking formula fixes are kept, because they are correct either way.

**How do I recompute a tracking formula's stored starting value?**
On **Actions → Incremental allocation** for a switched-on fund, click **Preview recomputing starting values**. Leave the date blank to use each tracking formula's latest stored date, or pick a date. The preview lists each folio's stored and recomputed values; **Apply** overwrites the stored ones.

**How do I add suggested run checks to a fund?**
On **Actions → Suggest run checks**, click **Generate suggestions** and wait. Tick the checks you want, choose **Fail (stops the run)** or **Warning** where offered, then click **Add selected**. They are added as enabled check formulas at the end of the fund's formula list.

**How do I review suggested checks before adding them, or add them to another copy of the fund?**
Tick them and click **Download selected as xlsx**. The file is in the fund formula upload format, so it can be edited and then uploaded with **Upload** on the fund's formulas page. Uploading it unchanged adds the same formulas **Add selected** would.

**How do I get AI suggestions for run checks?**
Click **Generate with AI** on **Actions → Suggest run checks**. It builds the rule suggestions and also asks AI for checks the rules do not cover, sending the fund's non-reporting formulas and uploaded entry names. AI suggestions are labelled **AI** and tested like the others; ones that fail formula validation are listed under **AI suggestions not offered**.

**Can I change a suggested check before adding it?**
You can switch its severity between **Fail (stops the run)** and **Warning** before **Add selected**. To change anything else, add it and then edit the formula, or download the xlsx, edit it and upload it.

### Why use incremental allocation

**Why switch a fund to incremental allocation?**
Allocation runs copy the fund's entries into a working file first, and formulas that total "since inception" need every entry back to the start. An incremental fund stores each total and adds only the movement since, so the copy only needs the current financial year and runs are faster. The numbers stay the same.

**Why add run checks before switching?**
The post-run check "Since Inception totals match history" compares each folio's stored total with the sum of all its entries. Run once before switching and once after, it shows the carried-forward totals are right, on the fund's real data. The page's recommended steps follow that order.

**Why are suggested checks tested before I add them?**
A pre-run check that fails stops every allocation run on the fund, so you should know what it will do first. Each suggestion is run against the fund's last successful allocation run and shows **Pass**, **Warn** or **Fail** with the reason and offending rows, without changing any data.

**Why use Warning instead of Fail for a check?**
A failed check stops the run: a pre-run check before anything is deleted, a post-run check before fund ratios, statements and the rest of a run group. A warning lets the run finish and records the finding on the run's check report. Use **Warning** for a check that fails today on data you cannot fix yet, such as missing exchange rates.

**Why are the suggestions rule-based rather than written by AI?**
Checks can stop allocation runs, so they must be the same every time and must not invent entry names. Rules produce the same checks from the same data and show what they found. **Generate with AI** adds AI suggestions for anything else, and they are validated and tested before they are shown.

### What happens when I …

**What happens when I preview switching a fund to incremental allocation?**
Nothing on the fund changes. A background job works out the formula changes and blockers, and loads a full copy of the fund to recompute tracking starting values, which can take a few minutes. You get an in-app alert when it is ready; no email is sent. Only one preview or apply can run on a fund at a time.

**What happens when I apply a switch to incremental allocation?**
The fund is checked again first. If nothing changed and no allocation run is in progress, the formula changes, their descriptions, the corrected starting values and the fund's switch are written together. Formula changes are recorded in the audit trail, the history shows **Applied**, and later runs carry totals forward.

**What happens if the fund changed after I made the preview?**
Apply writes nothing and shows **Refused** with "The fund has changed since this preview was made". That covers a formula or description edited since, or recomputed starting values that no longer match. Click **Preview again** and apply the new preview.

**What happens to allocation runs while a switch is being applied?**
While the status is **Applying**, starting a manual allocation run on the fund is refused with a message to wait, and an allocation run group that includes the fund is blocked at its checks. This stops a run reading the old formulas and the new setting at the same time. Apply takes seconds to minutes.

**What happens when I switch a fund off?**
Formulas the switch combined get back their earlier text and description from the audit trail, and runs go back to adding up full history. Tracking formula fixes and their descriptions stay. Stored totals are not deleted; the next run for each period recalculates them.

**What happens when I apply recomputed starting values?**
Each tracking formula's stored folio entries on the chosen date are overwritten with the total recomputed from the fund's full history. Entries that do not exist are left alone and none are created. There is no undo other than recomputing again, so check the preview's values first.

**What happens when I click Add selected?**
Each ticked suggestion becomes an enabled check formula with its name, description and formula, rule-for **Accounting**, placed after the fund's existing formulas. It runs on the next allocation run. The suggestion set records what was added, and the new formulas can be edited or disabled like any other.

**What happens when a suggested check fails in its test?**
Nothing is stopped: the test only shows what the check would say on the last successful run. If you add it with **Fail (stops the run)**, the next run fails at that check until the data is fixed. Add it as **Warning** instead, or fix the data first.

**Is anyone notified when a preview or apply finishes?**
Only the person who requested the preview, or who clicked **Apply**, gets an in-app alert when it finishes, with the outcome. No emails are sent and investors see nothing.

**Do investors see incremental allocation or run checks?**
No. Both are internal to the fund's allocation set-up. Investors see the same account entries and statements, which carry the same numbers either way.

### Troubleshooting and edge cases

**Why is the preview Blocked?**
Either a formula reads history in a way the switch cannot rewrite, or there is nothing to change. Blockers are listed with a link to each formula, for example "reads a date range with no start". Edit those formulas so they only read from the run's dates or carry their own total forward, then preview again.

**Why does Apply say an allocation run on this fund has not finished yet?**
An allocation run for the fund was started in the last 12 hours and has not reported a result, or a run group is using the fund. Wait for it to finish and click **Apply** again; the preview stays **Previewed**. A run stuck for more than 12 hours no longer blocks.

**Why does it say an operation is still previewing on this fund?**
Only one preview or apply can run on a fund at a time, so the page opened the one in progress. Wait for it to finish. One that has not finished within 12 hours is treated as failed and stops blocking.

**Why is a suggestion marked Already present?**
The fund already has a check calling the same helper with the same values, in any list order, at either severity. It cannot be added twice. Where the fund has a check using the same helper with different values, the suggestion names it instead.

**Why do all suggestions say Not tested?**
Suggestions are tested against the fund's last allocation run with status Success, and the fund has none. They can still be added. Run an allocation for a period, then click **Generate suggestions** again to see test results.

**Why doesn't the Since Inception check go Done on the recommended steps?**
Step 1 is done only when the fund has an enabled post-run check "Since Inception totals match history". Add it from **Suggest run checks**; it is suggested for any fund with formulas that store a "Since Inception" total.

**Why does the fourth recommended step stay open for a fund that is switched on?**
Step 4 looks for a successful allocation run after the switch was applied from this page. A fund switched on some other way has no recorded switch time, so the run after it cannot be identified. Its status still shows it is switched on.

**Why were some AI suggestions not offered?**
Every AI suggestion is checked like a hand-written formula. It is dropped if its text is unsafe (for example it contains "delete" or "update"), is not valid Ruby, or is not a pre-run or post-run check. Dropped ones are listed under **AI suggestions not offered** with the reason.

**The AI suggestions could not be generated. What now?**
The page says why, and the rule-based suggestions are unaffected and can still be added. Try **Generate with AI** again later, or add checks by hand.

---

## Related Guides

- [Formula Dependencies](formula_dependencies_user_guide) — see which formulas read each other before changing them
- [Allocation Run Templates](allocation_run_templates_user_guide) — run groups, which are blocked while a switch is being applied
- [Generate Account Entry Multiple](generate_account_entry_multiple_user_guide) — formulas that store one Since Inception total per name
- [Custom Fields](custom_fields_user_guide) — the entry and investment fields such as UDR codes that checks require
- [Fund Units](fund_units_user_guide) — unit settings that waterfall checks look for
- [Audit Trail](audit_trail_user_guide) — the record of every formula change a switch makes
