# Checking How a Fund's Formulas Depend on Each Other

Formulas rarely stand alone. One works out Net Income, the next uses that figure to work out a fee, a third rolls both into Closing Investable Capital. When a formula is renamed, disabled, or moved in the running order, anything downstream can quietly start reading a value that is no longer there — and the run either fails or produces a wrong number with no warning.

The **Dependencies** page shows those connections as a diagram, and flags the ones that are broken.

> **Where to find it:** Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Account Entries → Allocation Formulas** → **Dependencies**. Viewing needs the Funds module and access to the fund; editing a formula needs update rights on the fund.

This guide is for fund administrators who maintain allocation formulas.

---

## Opening It

Open the fund, choose **Actions → Account Entries → Allocation Formulas** (the **Fund Formulas** page) and click **Dependencies**.

Only the fund's **enabled** formulas are drawn; disabled formulas are left out of the diagram entirely, not just hidden. There is no filter control on the page, but it accepts `rule_for` and `tag_list` in its URL (for example `&tag_list=Quarterly`) to show only matching formulas.

You will see one card per formula, with arrows between them. An arrow means the formula it points *to* uses a value produced by the formula it points *from*. The label on the arrow is the value being passed.

- **Hover** a formula to preview its calculation.
- **Click** a formula to open its full details in a panel on the right, from where you can edit it. Press **Escape** or the **×** to close.

## Broken References

If anything is wrong, a red panel appears at the top of the page listing every problem, and the formulas involved are outlined in red in the diagram with a ⚠ marker.

There are two kinds:

**Nothing produces this value.** The formula reads something no other formula creates. Almost always a spelling mistake, or the formula that used to produce it was renamed or switched off.

**The value is produced too late.** The value does exist, but the formula that creates it runs at the same position or later in the sequence. When the reading formula runs, the value has not been worked out yet. Fix this by changing the sequence numbers so the producing formula runs first.

Both have the same effect at run time: the formula reads an empty value, and either fails or returns a figure that is wrong without looking wrong. This page is the quickest way to find them before a run rather than after.

It is worth opening this page after any of these:

- renaming a formula
- disabling or deleting a formula
- changing sequence numbers
- importing formulas into a new fund

## Formulas That Stand Alone

Most funds have formulas that neither feed another nor read one — they simply calculate and record a figure. These are hidden by default, so the diagram shows the actual chain of dependencies rather than a long column of unconnected cards.

Click **Show N unconnected formulas** to include them, and the same button again to hide them.

One exception: a formula with a broken reference is always shown, even if it is unconnected. In fact a broken formula is often unconnected *because* it is broken — the value it is trying to read does not exist, so there is no arrow to draw.

## Values the System Always Provides

Some values come from the system itself and are available to every formula, whatever else the fund contains. These never show as broken:

`@fund`, `@start_date`, `@end_date`, `@remittances_collected`, `@remittances_called`, `@remittance_capital_fees`, `@remittance_other_fees`, `@distributions`, `@income_before_start_date`, `@expense_before_start_date`, `@units`, `@start_of_financial_year`

Anything else a formula reads must be produced by a formula that runs earlier in the same run.

## A Note on "Add To Commitment Cache"

Each formula has an **Add To Commitment Cache** setting. It used to decide whether a formula's result was kept available for later formulas to use, and had to be switched on by hand — easy to forget, and the cause of values going missing downstream.

The system now works this out for itself. Before a run starts, it reads every formula and keeps exactly the values that later formulas actually ask for. **You no longer need to set this**, and leaving it off will not break a formula that depends on another.

The setting remains for the rare case where a value is referenced indirectly rather than by name. If you are ever told a value is missing at run time and the Dependencies page shows no problem, switching this on for the formula that produces it restores the old behaviour — and it is worth reporting, because it means the check missed something.

## What This Page Does Not Catch

The diagram is built from what each formula is written to read. It cannot tell you whether a figure is *correct* — only whether the values a formula depends on will be there when it runs. Reviewing the numbers themselves is still a separate exercise.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the formula Dependencies page in CapHive?**
Sidebar → [**Funds → Funds**](/funds), open the fund, then **Actions → Account Entries → Allocation Formulas** to reach the **Fund Formulas** page, and click **Dependencies**. See [Opening It](#opening-it).

**I can't see Allocation Formulas in the fund's Actions menu. Why?**
The **Account Entries** sub-menu appears only when account entries are enabled for your entity. The formulas list and the **Dependencies** button also need the Funds module and a non-investor login with access to the fund.

**How do I open a formula from the diagram?**
Click its card, or its name in the red broken-references panel, to open the formula's details in a panel on the right; hover a card to preview its calculation. Close the panel with **Escape** or **×**.

**Can I limit the diagram to Accounting or Reporting formulas, or to one tag?**
There is no filter control on the page. Adding a `rule_for` or `tag_list` parameter to the page's address in your browser (for example tag_list=Quarterly) shows only the matching formulas.

### Using the page and fixing problems

**Is there anything to create or save on the Dependencies page?**
No. The page is a read-only diagram built fresh from the fund's formulas each time you open it. You fix problems by editing the formulas themselves.

**How do I fix "no enabled formula produces this value"?**
Open the formula named in the red panel, click **Edit** and correct the `@value` spelling, or rename or re-enable the formula that should produce it. Reload **Dependencies** to confirm the warning is gone. See [Broken References](#broken-references).

**How do I fix "the formula that produces this value runs at the same position or later"?**
Edit the formulas' **Sequence** numbers so the producing formula has a lower sequence than the one that reads it, then reload the page.

**How do I show the formulas that are not connected to anything?**
Click **Show N unconnected formulas** above the diagram; click the button again to hide them. See [Formulas That Stand Alone](#formulas-that-stand-alone).

**Who can edit a formula from the panel?**
Users with update rights on the fund (granted on the fund's **Access** tab) or the company admin role see **Edit**, **Delete** and **Disable**/**Enable** on the formula. Creating new formulas with **New Fund Formula** is limited to CapHive support users.

### Why use the Dependencies page

**Why should I check formula dependencies?**
A renamed, disabled or re-sequenced formula can leave a later formula reading an empty value. The run then either fails or quietly produces a wrong figure, and this page shows those broken links before you run an allocation rather than after.

**What does the page let me do that the formula list does not?**
See which formula feeds which, with the passed value on each arrow, and get every broken reference listed in one place with the formulas outlined in red, instead of reading each formula's text by hand.

**When should I open it?**
After renaming, disabling or deleting a formula, changing sequence numbers, or importing or copying formulas into a fund, and before a period close.

**Who typically uses it?**
Fund administrators and CapHive support staff who maintain allocation formulas, and anyone investigating a run that failed or produced an unexpected number.

### What happens when I …

**What happens when I open the Dependencies page?**
The fund's enabled formulas are read in sequence order and each formula's `@value` references are matched to the formulas that produce them. Nothing is saved, no allocation runs, and no one is notified.

**What happens at run time if I ignore a broken reference?**
The formula reads an empty value for that name. Depending on the formula it either raises an error that fails the allocation run, or calculates a figure that is wrong without looking wrong.

**What happens when I disable a formula that other formulas use?**
Disabled formulas are left out of both allocation runs and this diagram, so every formula that read its value shows "no enabled formula produces this value" the next time you open the page.

**What happens to the Dependencies page when I use fund formula Bulk Actions → Disable or Enable?**
Bulk **Disable** on the Fund Formulas page switches off every formula matching the filter, so they drop out of this diagram and any formula reading their values shows as broken; bulk **Enable** brings them back. The bulk job runs in the background, so reopen this page after its "completed" alert. See [Bulk Actions on the Fund Formulas Page](generate_account_entry_multiple_user_guide#bulk-actions-on-the-fund-formulas-page).

**What happens to Add To Commitment Cache now?**
Before each run the system reads all formulas and keeps exactly the values later formulas reference, so you no longer need to tick it. Ticking it still forces a formula's value to be kept. See [A Note on "Add To Commitment Cache"](#a-note-on-add-to-commitment-cache).

### Troubleshooting and edge cases

**Why is my formula not in the diagram at all?**
Either it is disabled (only enabled formulas are shown), or it neither reads nor feeds another formula and is hidden; click **Show N unconnected formulas**. A formula with a broken reference is always shown.

**The page says there are no problems but a value is still missing at run time. What now?**
Tick **Add To Commitment Cache** on the formula that produces the value and re-run. Please report it too, since it means the value is referenced in a way the check could not see.

**Why do `@start_date` or `@remittances_collected` never show as broken?**
They are provided by the system to every formula: `@fund`, `@start_date`, `@end_date`, `@remittances_collected`, `@remittances_called`, `@remittance_capital_fees`, `@remittance_other_fees`, `@distributions`, `@income_before_start_date`, `@expense_before_start_date`, `@units` and `@start_of_financial_year`.

**How are value names matched to formula names?**
A formula's name becomes its value name in lower case with spaces as underscores, so "Net Income" is read as `@net_income`. A formula can also produce several names through `account_entry_names` in its meta data, and a GenerateAccountEntryMultiple formula produces one value per prefixed name, such as `@quarterly_management_fees`.

**Two formulas have the same sequence number. Is that a problem?**
It can be. A value produced by a formula at the same sequence is treated as not yet available, so the reader is flagged as "runs at the same position or later". Give the producer a lower number.

**Does a clean Dependencies page mean my numbers are right?**
No. It only confirms that the values each formula reads will exist when it runs; whether the calculations are correct still needs a separate review, for example with the Account Entries Period Report.

## Related Guides

- [Generate Multiple Account Entries](generate_account_entry_multiple_user_guide) — how a single formula produces several named values.
- [Allocation Run Templates](allocation_run_templates_user_guide) — running a fund's formulas for a period once the dependencies are clean.
- [Account Entries Period Report](account_entries_period_report_user_guide) — checking whether the figures the formulas produced look right.
- [Ratio Formulas](ratio_formulas_user_guide) — the separate formulas that feed fund ratios.
