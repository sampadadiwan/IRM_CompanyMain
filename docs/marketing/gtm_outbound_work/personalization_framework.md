# Personalization Framework

**Purpose:** convert the 10–15 minutes per account that `us_gtm_zero_budget_notes.md` §3.2 and §9 budget into a fixed, repeatable procedure. Without a framework, "research the account" expands to fill whatever time is available and produces a paragraph of flattery. With one, it produces two specific lines and stops.

**Companion docs:** [`adv_field_mapping.md`](adv_field_mapping.md) (where the data comes from) · [`sequences/`](sequences/) (where it goes) · [`qualification_screen.md`](qualification_screen.md) (what happens if they reply).

---

## 1. The rule that governs everything below

> **Personalization is a demonstration that we understand their problem. It is not a demonstration that we looked them up.**

"I saw you manage six funds" proves we ran a script. "Running six vehicles where two share an LP base means the allocation has to reconcile twice" proves we know what six vehicles costs them. The first reads as mail merge. The second reads as a peer.

The operational form of this rule: **every personalization token must be converted into a consequence before it enters the email.** The framework below is organised around that conversion — data point, then the consequence it licenses, then the line.

Three supporting rules:

- **One hook per email, in the first sentence.** Two hooks read as a dossier and trip the "how much do they know about me" reflex. The remaining research is not wasted — it is ammunition for the reply, the call and email 3.
- **The hook must be falsifiable-safe.** If we are wrong, being wrong must cost nothing. "It looks like at least one of your vehicles is organised in Cayman" survives being wrong. "Your Cayman feeder must be a nightmare" does not.
- **Never assert an inference as a fact.** Anything marked *heuristic* in `adv_field_mapping.md` §5 gets hedged in the copy — "looks like", "if I'm reading the filings right", "unless I've got the wrong fund". This is not weak writing; a CFO who reads a hedged, correct inference thinks *this person actually read my filing*.

---

## 2. The 12-minute timebox

Everything after minute 12 is a rounding error against a $60K+ ACV, but it is also the difference between 150 emails a week and 60. Hold the box.

| Minutes | Step | Output | Where it comes from |
|---|---|---|---|
| 0–1 | **Read the pre-computed row.** Do not re-derive anything the script already produced | Pass/fail confidence on the §1.1 profile | Filter output, `adv_field_mapping.md` §8 |
| 1–4 | **Pick the hook.** Walk the Tier 1 table in §3 top to bottom and take the *first* one that fires. Stop looking | One hook + its consequence sentence | ADV row |
| 4–8 | **Resolve the person.** Email finder → verify → confirm the title is current on LinkedIn. If no verified email in 4 minutes, park the account | Name, title, verified email, persona assignment | Email-finder tool (prerequisite C5) |
| 8–10 | **One Tier 2 check.** Website team page or a recent Form D filing date. This is the only off-ADV research allowed at this tier | Either a timing trigger or nothing — "nothing" is a valid answer | Firm website (ADV Item 1.I), EDGAR |
| 10–12 | **Assemble and QA.** Paste the sequence template, drop in the hook, run the checklist in §7 | Queued sequence | `sequences/` |

**Park, don't grind.** If the person cannot be resolved in 4 minutes, the account goes to a `needs-contact` list and the next account starts. Batch the parked ones weekly; some resolve when a new hire shows up on LinkedIn.

**Tier 3 — deeper research (podcast appearance, conference panel, a named LP, a recent deal) — is reserved for the top 50 accounts only**, and is done as a separate batch, not inline. Doing it for everyone is how 12 minutes becomes 40.

---

## 3. Tier 1 hooks — from the ADV row, zero extra research

Ordered by strength. Take the first that fires.

| # | Data point | ADV source | The consequence it licenses | Example line (adapt, do not paste) |
|---|---|---|---|---|
| 1 | **Self-administered** — no external fund administrator | Q26(a) = No on any fund | Every allocation, notice and reconciliation is their team's, not an admin's. Highest-fit signal we can see | "You're administering the funds in-house rather than through a third party — which means the close-percentage maths on every call lands on your team, not someone else's." |
| 2 | **Named fund administrator** | Q26(b) | We complement rather than replace — the objection-killer from `us_gtm.md` §1.3 lands before it is raised | "You're with {{Admin}} — so this isn't a pitch to replace them. The gap I keep hearing about is what happens on your side before the file goes to them." |
| 3 | **Master-feeder structure** | Q6(a)/(c) = Yes | Two sets of books, allocation through the master, LP-level reporting that has to reconcile back | "With {{FeederName}} feeding {{MasterName}}, the allocation has to land at the master and then be attributed back down. That reconciliation is the part that's manual almost everywhere." |
| 4 | **High non-US LP ownership** | Q16 > 25% on any fund | Multi-jurisdiction LP servicing; probable currency and documentation variation | "{{FundName}} looks like it's over a quarter non-US by beneficial ownership. That's usually where the per-LP variation in reporting starts." |
| 5 | **Offshore sibling vehicle** | Q2 non-US on one of several similarly-named funds | Parallel structure, dual documentation, dual close mechanics | "You've got {{FundA}} in Delaware and what looks like a Cayman sibling. Two closes, two sets of docs, one performance number that has to agree." |
| 6 | **Small vehicle beside a large one** | Q11 spread; likely-SPV score | Co-invest / SPV work is unbudgeted and rarely fits the system built for the flagship | "The flagship is one thing; it's the smaller vehicles alongside it that don't fit the process built for the flagship." |
| 7 | **Vehicle count itself** | `pf_count_effective` | Each vehicle adds a full workflow copy, not a fraction of one | "Six vehicles isn't six times one fund's work — it's six times the co-ordination, which is the part that doesn't compress." |
| 8 | **Administrator does not send LP statements** | Q26(e) = No or Some | The GP's own team is producing and sending investor statements | "Your administrator isn't sending the investor statements, which means someone on your side is." |
| 9 | **Mixed 3(c)(1) and 3(c)(7) estate** | Q4 varies across funds | Different eligibility rules per vehicle, different subscription handling | Use sparingly — it can read as showing off. |
| 10 | **Funds-of-funds on the register** | Q15(a) > 0% | Institutional LPs, heavier reporting and side-letter obligations | Best as a *second*-email hook, not a first. |

**Deliberately not hooks:** total RAUM ("congratulations on your $1.4B" is flattery and is often wrong because RAUM ≠ AUM), employee count, auditor name, anything from Item 11 disciplinary disclosure, and anything about the individual personally. See §6.

---

## 4. Tier 2 — one check, 2 minutes, off-ADV

Pick **one**, not all.

| Data point | Source | The line it powers |
|---|---|---|
| **Recent Form D or Form D/A** (last ~6 months) | EDGAR, via the `021-` number in Q22 | The timing trigger. "Looks like you're mid-raise on {{Fund}}" — an active close is the highest-urgency moment in `us_gtm.md` §4.1's "what accelerates the deal" |
| **Named ops/finance/IR hire or open role** | Firm website careers page, LinkedIn | "You're hiring into fund operations — which is usually a signal the current process is at capacity." Strong, and it is the honest version of the linear-headcount argument |
| **Team page shows a small back office** | Firm website | Confirms the ≤4-stakeholder screen and licenses "you're running this with a small team" |
| **Fund number / vintage in the fund name** | Q1(a), e.g. "Fund V" | Fund V with Funds II–IV still live means four vintages reporting concurrently |
| **Recent portfolio exit or new platform investment** | Firm news page | Only useful for the IR persona, and only if it implies a distribution or an LP update |

`TODO-VERIFY:` LinkedIn's terms restrict automated scraping. Tier 2 LinkedIn checks are assumed to be **manual** page views by the founder. Confirm before anyone automates this step.

---

## 5. Which hook goes to which persona

The same fact means different things to different buyers. Route it.

| Hook | CFO / Head of Finance | COO / Head of Operations | Director of Investor Relations |
|---|---|---|---|
| Self-administered | The controls sit with you, and so does the exposure | Your team is the fund admin | — |
| Named administrator | Reconciliation and the pre-wire check are still yours | The handoff to them is the manual part | They don't answer your LPs' questions |
| Master-feeder | Attribution back to the feeder has to survive an audit | Two closes, one investor list | LPs in the feeder get different documents |
| Non-US LPs >25% | Currency and withholding variation in the numbers | Different onboarding path per investor type | Per-LP reporting variation, different tax-season questions |
| Offshore sibling / parallel | Two sets of books, one performance figure | Two closes running in parallel | Two document sets for one commitment conversation |
| Likely SPV / co-invest | Carry on a deal-by-deal vehicle is its own calculation | Vehicles that don't fit the flagship's process | Co-invest LPs expect flagship-quality reporting on a $20M vehicle |
| Vehicle count | Consolidated reporting across vintages | Linear headcount per vehicle | More LPs asking the same ten questions per event |
| Active Form D | The close is coming and the numbers have to be right | The close is coming and the docs have to move | The close is coming and the LP experience is on display |

---

## 6. What we do not personalize on — and why

| Never use | Reason |
|---|---|
| **Item 11 disciplinary disclosure / any DRP** | It is public, and referencing it is instantly disqualifying in a market where — per `us_gtm_zero_budget_notes.md` §1 — one bad sequence damages the only asset we have |
| **AUM as a compliment** | RAUM is not AUM (it is gross and includes uncalled commitments), so the number is probably wrong, and flattery is the mail-merge tell |
| **Anything about the person individually** | Their alma mater, their move from a prior firm, their kid's soccer team. It reads as surveillance, not research |
| **A named competitor as a jab** | "Unlike Juniper Square…" invites a defence of a vendor they may like. Competitor framing belongs in a demo, not a first email |
| **An inference stated as fact** | See §1. "Your co-invest SPV" when Q1(a) actually names a continuation vehicle is a permanent loss |
| **Any capability not in the approved claim list** | See `sequences/README.md` §2. This is a hard rule, not a style preference |
| **Numbers we cannot source** | No "reduce LP service burden by 40%", no "cut quarter-close from 15 days to 4", until a customer has approved that wording in writing (prerequisite D1) |

---

## 7. Pre-send QA checklist

Run on every email. It takes 90 seconds and it is the difference between the list surviving and not.

1. Does the **first sentence** describe *their* situation, not us? If the word "CapHive" appears before the second paragraph, rewrite.
2. Is there **exactly one** personalization hook?
3. Is every **fund name, administrator name and jurisdiction spelled exactly** as it appears in the filing?
4. Is every **inference hedged** ("looks like", "if I'm reading it right")?
5. Does every **product claim** appear on the approved list in `sequences/README.md` §2?
6. Is every **link** to a URL on the verified list in `sequences/README.md` §3?
7. Are there **no numbers** we cannot attribute?
8. Is the body **under the word limit** for that email in the sequence?
9. Does the **ask** cost them less than 30 seconds to answer?
10. Is the CAN-SPAM footer present and is the unsubscribe live? *(Template mechanics are owned by prerequisite row C6 — this checklist only verifies the footer rendered.)*

---

## 8. Worked example

> ### ⚠️ HYPOTHETICAL — this firm does not exist
>
> **"Kestrel Ridge Partners" is invented for illustration.** Every figure below is fabricated to show the mechanics of the framework. It is not a real adviser, not a real filing, not a prospect, and no part of it may be reused as an example of a real account. Nothing here is a claim about any actual firm.

### 8.1 What the filter row would contain

| Field | Value |
|---|---|
| Legal name (Item 1.A) | Kestrel Ridge Partners LLC |
| Principal office (Item 1.F) | Boston, MA |
| Total RAUM (5.F.(2)(c)) | $1,180,000,000 |
| Pooled-vehicle RAUM (5.D.(3)(f)) | $1,140,000,000 (96.6% — passes the GP test) |
| Employees (5.A) | 24 |
| Advisory-function employees (5.B.(1)) | 15 → ~9 non-investment staff |
| CCO (1.J) | "Dana Whitcomb, Chief Financial Officer & Chief Compliance Officer" |
| `pf_count_7b1` | 4 |
| `pf_count_effective` | 5 (one feeder recovered from Q7) |
| Filing age | 7 months |

Per fund (Section 7.B.(1)):

| Q1(a) name | Q2 org | Q10 type | Q11 GAV | Q13 owners | Q16 non-US | Q26(a)/(b) admin | Q6 |
|---|---|---|---|---|---|---|---|
| Kestrel Ridge Fund IV, L.P. | Delaware | private equity fund | $610M | 185 | 12% | No — self-administered | — |
| Kestrel Ridge Fund IV (Offshore), Ltd. | Cayman Islands | private equity fund | $240M | 61 | 88% | No | feeder → Fund IV Master |
| Kestrel Ridge Fund III, L.P. | Delaware | private equity fund | $270M | 160 | 9% | No | — |
| KR Meridian Co-Invest, L.P. | Delaware | private equity fund | $38M | 19 | 4% | No | — |

**Derived:** `weighted_non_us_pct` ≈ 26% · `max_non_us_pct` = 88% · `lp_lower_bound` = 185 · `lp_upper_bound` = 425 · `likely_parallel_groups` = [Fund IV / Fund IV (Offshore)] · `likely_spv_fund_ids` = [KR Meridian Co-Invest] (name pattern + GAV 6% of flagship + 19 owners) · `self_administered` = true.

**§1.1 verdict:** AUM ✓ ($1.18B, in band) · vehicles ✓ (5 effective, includes a likely co-invest SPV *and* an offshore parallel/feeder) · LPs — plausible, needs confirming (185–425 spans the 150–400 band) · complexity ✓ (foreign LPs >25% weighted, and 88% on one vehicle) · stakeholders — unknown, ~9 non-investment staff and a dual-hatted CFO/CCO suggests small · tech posture — unknown.

### 8.2 Hook selection

Walking the Tier 1 table: **#1 fires immediately** — Q26(a) is "No" on every fund, so they self-administer. That is the strongest available signal and it is a fact, not an inference. Stop looking.

Held in reserve for email 3 and the call: the Cayman parallel (hook #5), the co-invest vehicle (hook #6), and the 88% non-US ownership on the offshore vehicle (hook #4).

### 8.3 Person resolution

Item 1.J names **Dana Whitcomb, CFO & CCO**. The dual title is itself the ≤4-stakeholder signal from `adv_field_mapping.md` §5.4. Persona: **CFO / Head of Finance**. Sequence: [`sequences/cfo_finance.md`](sequences/cfo_finance.md).

### 8.4 The resulting first email

**Subject:** Fund IV close percentages

> Dana —
>
> Kestrel Ridge looks to be administering the funds in-house rather than through a third party, which means the close-percentage maths on every Fund IV call lands on your team — and gets checked by the same people who produced it.
>
> The failure I hear about most isn't a wrong formula. It's that when someone asks six months later how a number was derived, the workbook that produced it has moved on.
>
> Wrote about that here: https://caphive.com/allocation-engine.html
>
> Worth 20 minutes?
>
> — {{SenderName}}

**Why this passes QA:** first sentence is about them (✓1); one hook, the self-administration fact (✓2); "Fund IV" spelled as filed (✓3); "looks to be" hedges a fact we are confident in but did not confirm (✓4); the only implied claim is that CapHive stores how a number was derived, which is on the approved list (✓5); the link is verified (✓6); no numbers (✓7); 79 words (✓8); the ask is one word to answer (✓9).

**What was left out, deliberately:** the $1.18B, the 24 employees, the co-invest vehicle, the Cayman feeder, the 88%. All correct, all interesting, all reserved. Putting them in would have produced a dossier.

### 8.5 What email 3 uses instead

If emails 1 and 2 get no reply, email 3 switches hook and angle rather than repeating: the Cayman sibling and the 88% non-US ownership, aimed at consolidated reporting across two vehicles that do not share a currency or a document set. Same account, different problem, different proof link — see `sequences/cfo_finance.md` email 3.

---

## 9. Storing the research so it is not re-done

One row per account in the sequencer, with these columns beyond the standard contact fields:

`hook_id` (which Tier 1 row fired) · `hook_text` (the actual sentence used) · `reserve_hooks` (comma-separated, for emails 3–4 and the call) · `persona` · `complexity_reason` (the reason string from the filter) · `admin_name` · `filing_age_months` · `form_d_recent` (bool) · `researched_by` · `researched_on`

Two reasons this matters more than it looks. First, when the reply comes weeks later, the reserve hooks are the call prep — and re-deriving them mid-call is not possible. Second, `hook_id` is the unit that `message_testing_plan.md` measures: without it, a low reply rate cannot be attributed to the hook rather than the message.
