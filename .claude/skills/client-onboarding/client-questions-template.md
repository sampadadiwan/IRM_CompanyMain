# Client questions template

Every onboarding keeps **one** client questions file: `<client>_client_questions.md` in the client workspace (e.g.
`inflexor_client_questions.md`). It is **mandatory** (SKILL.md hard rule 8): created right after profiling the source,
before the first import, and updated after every step that makes an assumption. It is written **for the client** — it
is the file ops sends them.

## Rules for writing it

1. **Every assumption has a question.** Anything taken from outside the client's files — a default, a placeholder, a
   reading of an ambiguous column, a fix to an inconsistent value — gets a question id (A1, B2, …) here, and the same id
   wherever the assumption is applied (the mapping yml's `q:`, the report's 1.7 table). The tools refuse an assumption
   whose id is not in this file.
2. **Quote the client's file**: file name, sheet, column (and row/folio where it matters), and the figures, so the client
   can check it in their own sheet.
3. **Say what we did for now** on its own line: `*What we did for now:* …`. The client confirms or corrects that, rather
   than answering from scratch.
4. **Mark blockers**: `(needed before go-live)` on anything that blocks investor access or a figure investors will see.
   Go-live cannot be ticked while one is unanswered.
4a. **The M section is fixed** (M1–M17, never renumbered, never removed): what every fund must have. M15–M17 are the
   portfolio items — keep them only when the portfolio (companies, investments, valuations, KPIs) is in scope. Each item ends with
   `*Status:* open | assumed | answered <date>`. Set `answered` only when the client has answered (and record the answer
   in the item); set `assumed` when we went ahead on an assumption. The tools read these lines (tools/gate.rb): a step
   runs only when its M items are answered, or in check-data mode for the data steps.
5. **Client language only**: no internal gap ids, code, endpoints or tool names. Amounts in the fund's convention
   (Indian grouping for INR), dates as the client writes them.
6. **Notes, not questions**, for things we handled that need nothing from them ("**F8. — note, nothing needed.** …").
7. Group by area; keep ids stable once sent (add new ones at the end of a section, never renumber).

## Template (copy from here; replace every `<…>`)

````markdown
# <Client> — client questions: <fund name> (before go-live)

We have loaded the files you shared into CapHive (in a test mode — nobody outside our team can see it and no emails go
out). Where something was missing, didn't match across files, or could be read more than one way, we made a reasonable
assumption so the work could go ahead. Each question below quotes what we see in your file and says **what we did for
now**. Please confirm or correct each one; anything you change, we update before go-live.

Amounts are in <currency>. Questions marked **(needed before go-live)** block investor access or figures investors will see.

---

## M. Must-have before we go on
These are what every fund needs from you. Until they are answered we can load your data to check it, but we cannot
give investors access or go live. Each says what we did for now; please confirm or correct.

**M1. Fund legal name, currency and SEBI category.** *What we did for now:* <…>
*Status:* open

**M2. Unit classes / series, and what differs between them** (fees, unit price, close). *What we did for now:* <…>
*Status:* open

**M3. First close date** (and final close, if any). *What we did for now:* <…>
*Status:* open

**M4. Management fee, set-up/other expenses, hurdle and carry, per class.** *What we did for now:* <…>
*Status:* open

**M5. Face value / issue price per unit for each class, and the allotment register if units are already issued.**
*What we did for now:* <…>
*Status:* open

**M6. For every investor folio: folio id, investor legal name, commitment amount and commitment date.**
*What we did for now:* <…>
*Status:* open

**M7. For every drawdown: amount called, notice date and due date** — and called = received + outstanding.
*What we did for now:* <…>
*Status:* open

**M8. For every payment received: date and amount** (bank reference if you have it). *What we did for now:* <…>
*Status:* open

**M9. Whether drawdowns include management fees or expenses** (and the split if they do). *What we did for now:* <…>
*Status:* open

**M10. Every distribution: gross, TDS, net, and the basis (income / return of capital / redemption).**
*What we did for now:* <…>
*Status:* open

**M11. Your own totals to check against** — total committed, called, received, distributed, and balance units per folio
if units are issued. *What we did for now:* <…>
*Status:* open

**M12. For every investor: real email address(es), PAN and investor type** (individual / company / LLP / trust / AIF).
*What we did for now:* <…>
*Status:* open

**M13. KYC documents / KYC status for every investor.** *What we did for now:* <…>
*Status:* open

**M14. Fund-ops review signed off** (internal — a fund-ops reviewer checked the loaded fund: calls, distributions, TDS,
units, statements). Set only by the reviewer: `answered <date> by <reviewer>`.
*Status:* open

**M15. Every portfolio holding: company legal name, each investment (date, instrument, quantity, amount paid) and the
latest valuation (date, per-share value, company valuation) — with your own total shares and stake value per company.**
*What we did for now:* <…>
*Status:* open

**M16. For every company: the KPIs you track and the exact line in its MIS each one comes from** (a KPI made of several
lines lists each line). *What we did for now:* <…>
*Status:* open

**M17. How each company reports: monthly or quarterly, the financial-year start, and the MIS files for each period.**
*What we did for now:* <…>
*Status:* open

## A. Fund set-up
**A1. <short title>.** In *<file>* (<sheet>), column <X> "<header>" <what we see, with figures>.
*What we did for now:* <the assumption>. <the question>?

## B. Investors and commitments
## C. Drawdowns and payments
## D. Distributions and units
## E. Portfolio companies, investments and valuations
## F. KPIs and MIS
````
