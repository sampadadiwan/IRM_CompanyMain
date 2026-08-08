# Side Letter Obligations Agent — User Guide

## What it does

Side letters create commitments your team must honour — quarterly reports for one
investor, fee arrangements for another, co-investment rights for a third. This agent
reads the side letter attached to each commitment, pulls out every obligation with the
exact clause it came from, and lines them all up for your legal team to review.

Once an obligation is approved, the system takes over the calendar: date-driven
obligations become tracked tasks (repeating automatically where the side letter calls
for it), and the owner gets an email before the due date, on the due date, and again
if it slips — escalating to your chosen team if something stays overdue.

Nothing goes live without a human saying so. Every extracted obligation waits in a
review queue where legal can approve it, correct it, or reject it. An obligation the
agent cannot tie to a specific clause in the document is discarded, never shown.

## Setting it up

1. **Enable the agent** for your firm (your administrator or CapHive support can do this),
   then run the agent setup so it appears on your Support Agents page.
2. On the agent's edit page, set:
   - **Side letter document name** — the exact name your side letters are uploaded
     under on each commitment (for example, "Side Letter"). The agent only reads
     documents with this name.
   - **Auto-extract on upload** — choose Yes if you want extraction to run the moment
     a side letter is uploaded; leave No to run it manually.
   - **Default reminder lead time** — how many days before a due date the first
     reminder goes out.
   - **Overdue escalation cadence** — how often overdue items are re-raised.
   - **Notify tag** — the team (by employee tag) that receives alerts for obligations
     without a named owner, and all overdue escalations.

## Day-to-day flow

1. **Upload** the executed side letter to the investor's commitment, using the
   configured document name.
2. **Extract** — run the agent for one commitment or the whole fund. Extracted
   obligations appear as "Pending review" in the Obligation Matrix.
3. **Review** — legal opens the matrix, checks each obligation against the cited
   clause, assigns an owner, and approves or rejects it. Items flagged
   "Changed on re-extraction" mean an amended side letter altered something that was
   previously approved.
4. **Track** — approved obligations with dates become tasks on the task board.
   Event-driven obligations (such as "notify the investor if a key person leaves")
   stay visible as "Armed" with no date; when the event happens, fire them with a
   deadline and a task is created on the spot.
5. **Complete** — finishing the task records the fulfilment, building an audit trail
   of who fulfilled what, when, and how. You can also record a fulfilment directly on
   the obligation page, attaching evidence if you have it.

## The Obligation Matrix

The matrix is the single view of every side letter obligation across all investors in
a fund: type, owner, next due date, and status. Filter it by obligation type, owning
team, due date range, review status, or MFN relevance. It is available from the
agent's page and as its own screen.

## Alerts

- **Upcoming** — sent to the obligation's owner ahead of the due date, using the lead
  time set on the obligation.
- **Due today** — sent on the due date.
- **Overdue** — repeated on the escalation cadence and copied to the notify tag team.

Each person receives one consolidated email per day listing everything that needs
their attention, worst first. Every alert sent is logged against the obligation.

## Good to know

- Setting an obligation's reminder lead time to zero suppresses the early reminder;
  due-today and overdue alerts still go out.
- Waiving an obligation removes its open tasks but keeps the history of what was
  already fulfilled.
- Re-running extraction after an amendment never overwrites approved obligations —
  changes arrive as new items for review.
- MFN-relevant obligations can be flagged during review so counsel can assess them
  across investors; the comparison dashboard is planned for a later release.
