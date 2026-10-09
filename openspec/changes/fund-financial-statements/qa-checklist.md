# Fund Financial Statements from Account Entries — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (IN), build under test |
| Accounts | **Meera** — employee with update access to Alpha Fund I · **Ravi** — employee with update access, user tag *FundAccounting* · **Priya** — employee with read-only access to Alpha Fund I · **Ops** — employee who can unlock allocation runs |
| Second entity | **Omar** — company admin of a different entity (Beta Capital) |
| Seed data | Entity *Alpha Capital*, fund **Alpha Fund I** (USD). Upload fund-level account entries for Q3 2026 (reporting dates in 1 Jul–30 Sep 2026): Non Deal Expense / Audit Fees 30,000 · Non Deal Expense / Legal Fees 15,200 · Deal Expense / Acme Ltd 62,400 · Non Deal Expense / Director Fees 8,000 · Tax / TDS 1,150 · Interest income cumulative 7,800 (30 Jun) and 11,900 (30 Sep) · Cash periodic 100,000 (31 Mar), -20,000 (30 Jun), 5,000 (30 Sep) · NAV / NAV Post Carry at 30 Sep. Run allocations for 1 Jul–30 Sep 2026 and **lock** the run (note its number, called **#3331** below). |
| Sample statement file | `fs_2025.pdf` — the fund's FY2025 statements (any PDF whose P&L prints "Professional fees 45,200" and "Other expenses 12,800"); `notes.docx` for the wrong-type test |
| Background work | **Generate** and **Regenerate** run in the background: refresh the Statements tab until the row leaves *Generating* (usually < 2 min). **Suggest from statements** also runs in the background: wait for the toast. If either is stuck > 10 min, ask a developer to check the job queue. |
| Direct requests | Rows marked *direct request* need a developer (or browser devtools) to send the request without the button |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H21 | Core statements appear | Alpha Fund I has never used Financial Statements | 1. As Meera open Alpha Fund I › Actions › Financial Statements 2. Mapping tab › Add account "Cash", type Asset 3. Save 4. Open Layout tab | Layout lists **Balance Sheet**, **Profit & Loss**, **Statement of Changes in Partners' Capital** | | |
| ☐ | H1 | Create an account | H21 done | 1. Mapping › Add account 2. Name "Professional fees", type Expense 3. Save | Account listed with behaviour **Movement**; Fund › Formulas shows a formula of type GenerateFinancialStatementLines | | |
| ☐ | H22 | Rename a core statement | H21 | 1. Layout › Profit & Loss › Rename to "Statement of Operations" 2. Save 3. Generate any period later and download PDF | Tab and PDF heading read "Statement of Operations" | | |
| ☐ | H23 | Add a schedule | H21 | 1. Layout › Add schedule 2. Name "Schedule of Fund Expenses", column style For a period 3. Save | Schedule appears in Layout; appears in the next generated statement set | | |
| ☐ | H2 | Subtotal adds up | P&L layout has Management fees (-250,000 for Q3) and Professional fees | 1. Layout › P&L › Add subtotal "Total expenses" of those two rows 2. Mapping › preview period Q3 2026 | "Total expenses" shows -295,200 (with Professional fees at -45,200) | | |
| ☐ | H3 | Reorder rows | P&L layout rows | 1. Drag "Professional fees" above "Management fees" 2. Reload | New order kept; preview and next generation use it | | |
| ☐ | H24 | Same account on two statements | Audit fees account on P&L and on Schedule of Fund Expenses | 1. Generate Q3 2026 2. Open P&L, then the schedule | Both show Audit fees 30,000 | | |
| ☐ | H4 | Any-name rule catches a new name | Rule Deal Expense (any name) → Transaction costs | 1. Upload a new entry Deal Expense / Acme Ltd 62,400 for Q3 2026 2. Mapping › preview Q3 2026 | Transaction costs preview 62,400; nothing new in Unmapped | | |
| ☐ | H5 | Exact rule beats any-name rule | Rules: Non Deal Expense (any) → Other expenses; Non Deal Expense / Audit Fees → Professional fees | 1. Preview Q3 2026 | Audit Fees' 30,000 counted only in Professional fees | | |
| ☐ | H6 | Unmapped entry listed | Director Fees 8,000, no rule | 1. Mapping › preview Q3 2026 | Unmapped panel row "Non Deal Expense · Director Fees · 8,000" with **Map** | | |
| ☐ | H7 | Map from the Unmapped list | H6 | 1. Click Map 2. Choose Professional fees 3. Save | Row leaves Unmapped; Professional fees preview rises by 8,000 | | |
| ☐ | H8 | Preview updates on rule change | Rule Tax / TDS → Excluded | 1. Edit rule to Other expenses 2. Save | Other expenses preview rises by 1,150 without a page reload; no new account entry in Fund › Account Entries | | |
| ☐ | H9 | Movement from cumulative entries | Interest income mapped | 1. Preview Q3 2026 | Interest income 4,100 | | |
| ☐ | H10 | Balance from periodic entries | Cash mapped | 1. Preview Q3 2026 (at 30 Sep) | Cash 85,000 | | |
| ☐ | H11 | AI draft matches printed figure | Fund with entries at the as-at date | 1. Mapping › Suggest from statements 2. Upload `fs_2025.pdf`, as at 30 Sep 2026 3. Wait for toast 4. Open the draft | Professional fees line shows printed 45,200 / CapHive 45,200 with ✓; nothing saved yet | | |
| ☐ | H12 | Generate a statement set | Mapping complete, run #3331 locked | 1. Statements › Generate statements 2. 1 Jul 2026 – 30 Sep 2026 3. Wait for Draft | Row "01/07/2026 – 30/09/2026 · Draft"; opening it shows "Built from accounting run #3331"; switcher lists Balance Sheet, P&L, Changes in Capital, schedule; Fund › Account Entries filtered by entry type "Financial Statement" shows entries dated 30/09/2026, none for any investor | | |
| ☐ | H13 | Accounting numbers untouched | Before H12, export Q3 account entries (excluding Financial Statement) | 1. After H12, export again 2. Compare | Identical rows and amounts | | |
| ☐ | H14 | Allowed although accounting run is locked | Run #3331 locked | 1. Generate Q3 2026 | Generation starts (no "locked" alert) | | |
| ☐ | H15 | Lock | Draft with all checks ✓ and 0 unmapped | 1. As Ravi open the draft 2. Lock | "Locked on <today> by Ravi"; Regenerate hidden; Fund › Allocation runs shows the statements run locked | | |
| ☐ | H16 | Unlock warns | Q3 2026 statements locked | 1. As Ops open Fund › Allocation runs 2. Click Unlock on run #3331 | Popup with cards: runs unlocked · "Q3 2026 statements back to Draft" · "Fund accounting notified"; buttons Cancel / Unlock anyway | | |
| ☐ | H17 | Confirmed unlock | H16 | 1. Unlock anyway 2. Open Financial Statements 3. Check Ravi's inbox and bell | Runs unlocked; Q3 2026 row is Draft; Ravi receives exactly one email and one in-app alert naming Ops, the fund and the period | | |
| ☐ | H18 | Prior year from frozen copy | FY2025 statements locked with Professional fees 88,400; afterwards edit a FY2025 Audit Fees entry | 1. Generate and open Q3 2026 2. Look at the "same period last year" column | Shows the locked figure, marked "Changed since locked" | | |
| ☐ | H19 | Draft downloads | Q3 2026 Draft with expense schedule | 1. Download PDF 2. Download Excel | Every PDF page watermarked "DRAFT"; Excel has 4 sheets, one per statement | | |
| ☐ | H20 | Read-only user | — | 1. As Priya open Financial Statements | Can open and download; no Generate, Lock, Regenerate, or mapping/layout editing controls | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Same period twice | Q3 2026 Draft exists | 1. Generate 1 Jul–30 Sep 2026 again | Still one row for that period; figures refreshed | | |
| ☐ | E2 | Excluded entries | Rule Portfolio Allocation (any) → Excluded | 1. Preview Q3 2026 | Those amounts in no line and not in Unmapped | | |
| ☐ | E3 | Investor-level entries ignored | Upload folio F-102 Audit Fees 500 for Q3 | 1. Preview Q3 2026 | Professional fees unchanged | | |
| ☐ | E4 | Rounding tolerated | Ask developer for fund data giving a Balance difference of 0.40 | 1. Generate | Balance check ✓ | | |
| ☐ | E5 | Exactly 1.00 fails | Data giving difference 1.00 | 1. Generate | Balance check ✗ with difference 1.00 | | |
| ☐ | E6 | No NAV entry | NAV entry set in settings; delete the 30 Sep NAV entry | 1. Generate Q3 | NAV tie-out "Skipped — no NAV entry"; Lock still possible | | |
| ☐ | E7 | Capital check not configured | Settings: capital entry blank | 1. Generate Q3 | Partners' capital tie-out "Skipped — not configured" | | |
| ☐ | E8 | Unlock with nothing locked | Q3 statement is Draft | 1. Unlock run #3331 | Plain confirm as before; no notification sent | | |
| ☐ | E9 | No drift | Q2 2026 locked, nothing changed | 1. Open Q2 2026 | No yellow banner | | |
| ☐ | E10 | Drift banner | Q2 2026 locked with Professional fees 45,200 | 1. Edit Q2 Audit Fees 30,000 → 32,700 2. Open Q2 2026 3. Download PDF | Banner "Changed since locked: Professional fees 45,200 → 47,900"; PDF still shows 45,200 | | |
| ☐ | E11 | First year | No locked FY2025 statement | 1. Open Q3 2026 | Prior-year column headed "Not locked — computed" | | |
| ☐ | E12 | Ordinary run skips statement lines | Q2 2026 unlocked; Q2 statements generated | 1. Fund › Allocate Q2 2026, no tags 2. After it finishes, filter account entries by "Financial Statement" for Q2 | Same Financial Statement entries as before (none added or removed) | | |
| ☐ | E13 | Mixed cumulative and periodic | Upload a periodic Interest income entry for Q3 too | 1. Preview Q3 | Interest income still 4,100 (cumulative used); warning shown | | |
| ☐ | E14 | Period boundaries | Entries dated 30 Jun, 1 Jul, 30 Sep (Other expenses) | 1. Preview Q3 2026 | 1 Jul and 30 Sep included; 30 Jun excluded | | |
| ☐ | E15 | Unlock all, two periods | Q2 and Q3 2026 locked | 1. Allocation runs › Unlock All › confirm | Both Draft; Ravi gets one notification listing both periods | | |
| ☐ | E16 | Regenerate replaces lines | Draft; add one new account and rule | 1. Regenerate | Financial Statement entries for the period now include the new account; none duplicated | | |
| ☐ | E17 | Statement lines never shown as unmapped | After H12 | 1. Mapping › Unmapped for Q3 | No "Financial Statement" rows | | |
| ☐ | E18 | AI mismatch flagged | `fs_2025.pdf` prints Other expenses 12,800 | 1. Suggest 2. Open draft | Other expenses ⚠ printed 12,800 / CapHive 11,650, difference 1,150 | | |
| ☐ | E19 | Discard draft | Ready draft | 1. Discard 2. Open Mapping | Accounts, rules and layout unchanged | | |
| ☐ | E20 | Draft against an existing mapping | Fund already mapped | 1. Suggest again 2. Approve | Draft marks lines added/changed; after approve no duplicate account names | | |
| ☐ | E21 | April financial year | Settings › financial-year start = April | 1. Generate Q3 2026 | YTD column covers 1 Apr–30 Sep 2026 | | |
| ☐ | E22 | Zero total not unmapped | Unmapped pair with +500 and -500 in Q3 | 1. Mapping › Unmapped Q3 | Pair not listed | | |
| ☐ | E23 | Cancel the unlock popup | Q3 locked | 1. Unlock › Cancel | Runs and statement still locked; no notification | | |
| ☐ | E24 | Flip sign | Distributions entries stored negative; account "Distributions" with flip sign on | 1. Preview / generate Q3 | Distributions shown positive on Changes in Partners' Capital; roll-forward ✓ | | |
| ☐ | E25 | Double-click Generate | — | 1. Double-click Generate (or two tabs, both submit) | One statements run; second attempt shows "An allocation run is in progress for this fund. Try again when it finishes." | | |
| ☐ | E26 | Re-lock after unlock | After H17, regenerate | 1. As Ravi Lock again | New figures frozen; drift banner gone | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No accounting run | No successful run for Q4 2026 | 1. Generate 1 Oct–31 Dec 2026 | "Run and complete the fund's allocations for this period first." | | |
| ☐ | X2 | Run in progress | Start any allocation run on the fund | 1. While it runs, Generate | "An allocation run is in progress for this fund. Try again when it finishes." | | |
| ☐ | X3 | Regenerate a locked set | Q3 locked | 1. *Direct request*: regenerate Q3 | "These statements are locked." | | |
| ☐ | X4 | Ordinary run still blocked | Run #3331 locked | 1. Fund › Allocate 1 Jul–30 Sep 2026 | Existing alert "This AllocationRun already exists for the specified period and is locked…" | | |
| ☐ | X5 | Duplicate account name | Professional fees exists | 1. Add account "Professional fees" | "Name has already been taken" | | |
| ☐ | X17 | Delete a core statement | — | 1. Layout › Balance Sheet › Delete | "Core statements can be renamed but not deleted" | | |
| ☐ | X6 | Delete an account in use | Rule targets Professional fees | 1. Delete Professional fees | Refused; message names the rule(s) using it | | |
| ☐ | X7 | Wrong file type | — | 1. Suggest from statements 2. Upload `notes.docx` | "Upload a PDF or Excel file" | | |
| ☐ | X8 | Lock blocked by unmapped | Draft with 2 unmapped | 1. Open draft | Lock disabled; "Map or exclude 2 entries before locking" | | |
| ☐ | X9 | Lock blocked by failed check | Draft with Partners' capital tie-out ✗ | 1. *Direct request*: lock | Refused; statement stays Draft | | |
| ☐ | X10 | Balance check fails | Assets 10,000,000, liabilities 200,000, capital 9,798,800 | 1. Generate | Balance ✗ difference 1,200; Lock disabled | | |
| ☐ | X11 | Statements run fails | Ask developer to break the statement formula | 1. Generate | Row shows Failed with a link to the run; Meera gets the usual allocation-run failure notice | | |
| ☐ | X12 | AI failure | Ask developer to make the AI call fail | 1. Suggest | Draft Failed with the error and **Retry**; Meera sees a toast | | |
| ☐ | X13 | Read-only lock attempt | Priya | 1. *Direct request*: lock Q3 as Priya | Not authorised; statement unchanged | | |
| ☐ | X14 | Other entity | Note a statement URL from Alpha Fund I | 1. As Omar open that URL | Not found | | |
| ☐ | X15 | Statement formula disabled | Fund › Formulas › disable the statement formula | 1. Generate | "Enable the fund's financial statement formula first." | | |
| ☐ | X16 | Locked statements run overlapping | Lock the statements run from Fund › Allocation runs, statement still Draft | 1. Generate same period | "Unlock the statements run for this period first." | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Fund › Actions | Click **Financial Statements** | Page with tabs Statements · Mapping · Layout; ① Generate statements button (users with update access) | | |
| ☐ | J1.2 | Statements tab | Generate 1 Jul–30 Sep 2026 | ② New row "Generating…" that turns into Draft without a manual refresh | | |
| ☐ | J1.3 | Statement view | Open the Draft | ③ Statement switcher, columns this period / YTD / last year, Checks panel, unmapped count, Regenerate | | |
| ☐ | J1.4 | Statement view | Fix mapping via the Unmapped link, Regenerate | Figures replaced, checks re-run | | |
| ☐ | J1.5 | Statement view | ④ Lock | "Locked on … by …"; Regenerate hidden | | |
| ☐ | J2.1 | Mapping tab | Pick preview period | Rules, Preview column, Unmapped panel all for that period | | |
| ☐ | J2.2 | Mapping tab | Add / edit / delete a rule | Rules, preview and Unmapped update in place | | |
| ☐ | J3.1 | Mapping › Suggest from statements | Upload file + as-at date | Draft page "Processing", then lines with printed / CapHive / ✓⚠ | | |
| ☐ | J3.2 | Draft page | Approve draft | Back on Mapping with the new accounts, layout and rules | | |
| ☐ | J4.1 | Fund › Allocation runs | Unlock on a period with locked statements | Action-summary popup (3 cards), Cancel / Unlock anyway | | |

---

## Role Sweep

| ID | Screen / action | Meera (update) | Ravi (update, FundAccounting) | Priya (read-only) | Investor | Omar (other entity) |
|---|---|---|---|---|---|---|
| R1 | Open Financial Statements | ✓ | ✓ | ✓ | ✗ | ✗ |
| R2 | Download Excel / PDF | ✓ | ✓ | ✓ | ✗ | ✗ |
| R3 | Generate / Regenerate | ✓ | ✓ | ✗ | ✗ | ✗ |
| R4 | Lock | ✓ | ✓ | ✗ | ✗ | ✗ |
| R5 | Edit accounts, rules, layout, settings | ✓ | ✓ | ✗ | ✗ | ✗ |
| R6 | Suggest from statements / Approve draft | ✓ | ✓ | ✗ | ✗ | ✗ |
| R7 | Receives "Financial statements unlocked" | only if tagged FundAccounting | ✓ | only if tagged and can see the fund | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | "Financial statements unlocked" email and alert | Sent to Ravi only; subject names fund; link opens the statement; dates like `Sep 30, 2026` | | |
| ☐ | C2 | Dates on the new screens and the Excel/PDF | Follow the user's locale (e.g. `30/09/2026` for en, `09/30/2026` for en-US) | | |
| ☐ | C3 | Narrow / mobile width | Statement tables scroll inside their card; no page-level horizontal scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Omar cannot see or reach any statement, mapping, draft or download, even with direct URLs | | |
| ☐ | C5 | Regression on modified screens | Fund › Allocation runs Unlock / Unlock All behave exactly as before when no statements are locked; Fund › Allocate unchanged; fund Actions menu otherwise unchanged | | |
| ☐ | C6 | Empty states | New fund: Statements "No statements yet"; Mapping "No accounts yet — add one or Suggest from statements"; Unmapped "Everything is mapped" | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
