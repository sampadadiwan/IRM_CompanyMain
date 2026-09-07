# Allocation Run Checker

**Status:** Sections 1 and 2 are built and in use. Section 3 is still a proposal — nothing in
it has been built, and the questions under it are still open.

## What this is

After an allocation run finishes for a fund and period, a reviewer runs the checker over it and
gets a short Pass / Warn / Fail report before anyone locks it. The checks below are deliberately
few.

Every check answers one of three questions.

## How you use it

On the allocation screen, every past run has a check button among its actions. Pressing it runs
the checks and opens the report; the run's Status cell then carries a Pass, Warn or Fail badge
underneath the run's own status, linking back to the report. Until then it reads "Not checked".
Checking a run again replaces its report, so the badge is always the latest answer.

The report itself has three tabs: a summary, the section 1 checks and the section 2 checks. Each
check shows its result, a plain sentence saying what it found, and the folios or entry names
affected. Long lists are cut off after fifty rows with a count of the rest.

Every row that names an entry or a folio has a link straight through to those account entries,
already filtered to the right period — so a failure takes you to the numbers behind it rather
than leaving you to search for them. There is also an **Account Entries** button at the top of
the report for everything the run produced — the same list the allocation screen's own entries
link shows for that run.

The report never locks or unlocks anything. Locking stays your decision.

## Checking a run long after it ran

Nothing has to be switched on before a run finishes. The checks are worked out from the ledger
as it stands when you press Check, so any past run can be checked at any time, and checked again
later. That is the point rather than a limitation: most of these checks would agree with
themselves at the moment a run ends, and only start to earn their keep once the numbers have had
time to move underneath them.

Two things to know about older runs:

- **A run made before March 2025** — the system did not yet record which run produced which
  entry. The three checks that ask "what did *this* run produce?" (1.2, 1.3 and 2.1) say so and
  are skipped. They are not reported as failures.
- **A run made before July 2024** — the system did not yet record whether a run succeeded, so
  check 1.1 is skipped for the same reason.

Everything else still works on a run of any age, including **check 2.2**, which is the one worth
having on old periods: it is what finds an entry back-dated into a period that was closed years
ago. If nothing at all could be checked, the report says "Nothing to check" rather than showing
a green Pass.

If you want reports across a whole fund or a whole entity at once rather than run by run, that
can be done in one go — ask and we will run it.

## 1. Did the run happen correctly? — built

| # | Check | Result if it fails |
|---|-------|--------------------|
| 1.1 | The run finished with status Success | Fail |
| 1.2 | Every enabled formula for the fund produced at least one entry | Warn, listing the silent formulas |
| 1.3 | Every folio with a commitment dated on or before the period end received entries | Warn, listing the missing folios |
| 1.4 | The period starts the day after the previous locked run ended (no gap, no overlap) | Warn |

## 2. Do the numbers add up? — built

These hold regardless of what the formulas say, so a failure here is a real defect.

| # | Check | Result if it fails |
|---|-------|--------------------|
| 2.1 | For every entry name, the fund-level total equals the sum of the folio-level entries | Fail, per entry name |
| 2.2 | For cumulative entries, this period's cumulative equals everything that went into it since the fund started | Fail, per folio and entry name |
| 2.3 | Percentage-type allocations across folios sum to 100% | Fail, per entry name |

## 3. Do the numbers look reasonable? — not built

These compare against the previous run and the fund's terms. They are always warnings,
because a genuine event (a large drawdown, a fee step-down) will trip them.

None of this is built. Every check here needs to know which entry names on your funds mean NAV,
management fee, carry or units, and the system does not know that today — see the first question
below.

| # | Check | Default tolerance | Result if it fails |
|---|-------|-------------------|--------------------|
| 3.1 | Each fund-level total moved by no more than X% versus the previous run | 25% | Warn, showing old vs new |
| 3.2 | Each folio's share of a pro-rata entry matches its share of total commitment | 0.5% | Warn, listing outlier folios |
| 3.3 | Entries that should never be negative (units, commitment, NAV) are not negative | none | Warn |
| 3.4 | Portfolio valuations and FX rates used were dated within the period end window | 30 days / 5 days | Warn (this reuses the existing pre-run validation rules) |

## What the business needs to tell us

These questions are all about section 3 and what comes after it. Sections 1 and 2 needed none
of them, which is why they went first.

1. **Which entry names matter for check 3.2 and 3.3.** The system does not know which
   names represent NAV, management fee, carry, or units. We need the names used on your
   funds. Nothing in section 3 can be built until we have them.
2. **The default tolerances above.** Are 25% and 0.5% sensible starting points?
3. **When it should run.** Today it runs on demand, from the check button on the allocation
   screen. The other options are automatically after every allocation run, or nightly across
   unlocked runs. Our recommendation is still automatically after every run.
4. **Who gets the report.** Today it is a page and nothing is emailed. The options are an email
   to the person who ran the allocation, a fixed finance mailbox, or both.

## Where AI fits — not built

The checks above are arithmetic and lookups. They are computed directly, not by AI, so
the Pass / Warn / Fail result is the same every time and can be audited. That is true of what is
built today: no part of the current checker uses AI.

Everything in this section is a proposal that only starts to earn its keep once section 3 exists.
Sections 1 and 2 say exactly what is wrong — a formula produced nothing, a total is out by an
amount — so there is nothing for an investigator to work out.

AI would be used only after a check has failed, to explain it. Each warning is handed to an
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

## What is deliberately out of scope

- Re-computing fees or carry from the fund's terms. This needs per-fund configuration
  and is better added once the basic checks have earned trust.
- Any check that requires reading the formula code itself.
- Blocking the lock action. The checker only reports; locking stays a human decision.
- **Two checks that were on the original list and are not built: "no folio has the same entry
  name twice for the same date" and "no entry has a blank or non-numeric amount."** The second
  is mostly moot — amounts are stored in a numeric column, so a non-numeric amount cannot be
  saved. The first is not moot: the engine inserts entries in bulk, which skips the duplicate
  check the system applies to entries entered by hand, and there is no database constraint
  behind it. If duplicated entries are something you have actually seen, say so and it goes
  back on the list.
- **Telling a sample run apart from a real one.** A sample run is a debugging option that stops
  the engine after three folios. Which runs were sample runs is not recorded, so afterwards a
  sample run cannot be distinguished from a run that genuinely missed every other folio — check
  1.3 warns about both, and the warning is worth reading either way. Recording it on the run
  would turn this into a real check, and is a small change if you want it.

## How it appears

- A Pass / Warn / Fail badge in a Check column on the allocation run row on the allocation
  screen, next to a button that runs the checks. **Built.**
- A report page listing each check, its result, and the affected folios or entry names.
  **Built.**
- An optional email with the same content. **Not built** — see question 4 above.
