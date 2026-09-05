# Allocation Run Checker — proposed checks for business review

**Status:** Draft for discussion. Nothing is built yet.

## What this is

After an allocation run finishes for a fund and period, an agent reviews the run and
produces a short pass / warn / fail report before anyone locks it. The checks below are
deliberately few. We want to confirm with the business that these are the right ones
before adding more.

Every check answers one of three questions.

## 1. Did the run happen correctly?

| # | Check | Result if it fails |
|---|-------|--------------------|
| 1.1 | The run finished with status Success | Fail |
| 1.2 | Every enabled formula for the fund produced at least one entry | Warn, listing the silent formulas |
| 1.3 | Every folio with a commitment dated on or before the period end received entries | Warn, listing the missing folios |
| 1.4 | The period starts the day after the previous locked run ended (no gap, no overlap) | Warn |
| 1.5 | The run was not a sample run (a few folios only) | Fail |

## 2. Do the numbers add up?

These hold regardless of what the formulas say, so a failure here is a real defect.

| # | Check | Result if it fails |
|---|-------|--------------------|
| 2.1 | For every entry name, the fund-level total equals the sum of the folio-level entries | Fail, per entry name |
| 2.2 | For cumulative entries, this period's cumulative equals the previous cumulative plus this period's amount | Fail, per folio and entry name |
| 2.3 | Percentage-type allocations across folios sum to 100% | Fail, per entry name |
| 2.4 | No folio has the same entry name twice for the same date | Fail |
| 2.5 | No entry has a blank or non-numeric amount | Fail |

## 3. Do the numbers look reasonable?

These compare against the previous run and the fund's terms. They are always warnings,
because a genuine event (a large drawdown, a fee step-down) will trip them.

| # | Check | Default tolerance | Result if it fails |
|---|-------|-------------------|--------------------|
| 3.1 | Each fund-level total moved by no more than X% versus the previous run | 25% | Warn, showing old vs new |
| 3.2 | Each folio's share of a pro-rata entry matches its share of total commitment | 0.5% | Warn, listing outlier folios |
| 3.3 | Entries that should never be negative (units, commitment, NAV) are not negative | none | Warn |
| 3.4 | Portfolio valuations and FX rates used were dated within the period end window | 30 days / 5 days | Warn (this reuses the existing pre-run validation rules) |

## What the business needs to tell us

1. **Which entry names matter for check 3.2 and 3.3.** The system does not know which
   names represent NAV, management fee, carry, or units. We need the names used on your
   funds.
2. **The default tolerances above.** Are 25% and 0.5% sensible starting points?
3. **When it should run.** Options are automatically after every allocation run,
   nightly across unlocked runs, or on demand from the allocation screen. Our
   recommendation is automatically after every run.
4. **Who gets the report.** Email to the person who ran the allocation, a fixed
   finance mailbox, or both.

## Where AI fits

The checks above are arithmetic and lookups. They are computed directly, not by AI, so
the Pass / Warn / Fail result is the same every time and can be audited.

AI is used only after a check has failed, to explain it. Each warning is handed to an
investigator that works like an analyst opening the entries screen: it follows a written
runbook, looks at the affected numbers, and writes a short explanation.

**The runbook.** A document attached to the agent that says, for each kind of warning,
what to look at. For example, when a fund-level total moves more than the tolerance:
compare the folio breakdown across the two runs, check whether the commitment base
changed, read the formula's description, and read the calculation note the system
stores on a sample entry. The business can edit this document without a code change.

**What the investigator can look at.** A small fixed set of views, not free-form access:

- Totals by entry name for this run and the previous run.
- Folio-by-folio breakdown of one entry name, for this run and the previous run.
- The formula description and the stored calculation note for a single entry.
- Each folio's share of total commitment.

**What it produces.** For each warning, a likely cause, the evidence it used, a confidence
level, and whether it looks like a genuine business event or a defect. The explanation is
labelled as a suggestion. The reviewer marks it as accepted or not, which tells us over
time whether the explanations are worth trusting.

**Limits.** The investigator never changes the Pass / Warn / Fail result, never feeds the
lock decision, and is capped at a small number of lookups per warning.

**Asking questions afterwards.** Once the report exists, a reviewer can ask questions
in plain language against it, such as "why did folio 42 receive less than its share?",
using the same views listed above.

## What is deliberately out of scope for the first version

- Re-computing fees or carry from the fund's terms. This needs per-fund configuration
  and is better added once the basic checks have earned trust.
- Any check that requires reading the formula code itself.
- Blocking the lock action. The first version only reports; locking stays a human decision.

## How it would appear

- A Pass / Warn / Fail badge on the allocation run row on the allocation screen.
- A report page listing each check, its result, and the affected folios or entry names.
- An optional email with the same content.
