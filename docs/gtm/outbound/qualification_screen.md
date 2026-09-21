# Discovery Call Qualification Screen

**Purpose:** test the [`us_gtm_zero_budget_notes.md`](../us_gtm_zero_budget_notes.md) §1.1 profile in 30 minutes without the call feeling like a procurement interview, and decide — on the call — whether this account gets founder time.

**Why this document exists at all.** The plan needs 12–20 real opportunities, not 200 leads (§1). Founder capacity is the binding constraint, and the way it gets destroyed is not by too few meetings — it is by four months spent on an account that was never going to close. **The disqualification criteria in §7 are the load-bearing part of this document.** Everything above them is how you get to the point where you can apply them.

**Frame** (`us_gtm.md` §4.4 step 3): this is an operational problem exploration between peers, not a vendor demo. The words "our platform" should not appear in the first twenty minutes.

---

## 1. Before the call — 5 minutes

Re-read the ADV row. **You already know their vehicle count, fund types, jurisdictions, non-US ownership percentage, fund administrator, auditor and rough size.** Asking questions ADV already answered wastes the only 30 minutes you get and signals you did not prepare.

Write down three things on one line each:

1. **What you know** — "5 vehicles, one Cayman parallel, self-administered, 88% non-US on the offshore vehicle"
2. **What you inferred and need confirming** — "the small vehicle looks like co-invest"
3. **What ADV cannot tell you** — always: side letter count, currency handling, carry mechanics, buying group, tech posture

Only #2 and #3 are questions. #1 is context you demonstrate in one sentence and then move past.

---

## 2. Open — 2 minutes

> "Thanks for the time. To be straight about why I asked: I've been looking at how mid-market GPs handle the operational gap between their fund admin, their counsel and their LP base — particularly around closes, obligations and reporting across multiple vehicles. I've read your filings, so I know roughly the shape — {{one sentence of what you know}}. What I don't know is where the friction actually is.
>
> So mostly I want to ask questions. If it turns out we're not useful to you, I'd rather find that out in the next twenty minutes than in three months."

That last sentence does more work than anything else in this document. It makes disqualification a shared activity rather than something you do to them, and it earns candour on everything that follows.

---

## 3. The anchor question — ask it first, then be quiet

> **"Tell me about the most painful investor situation you've dealt with in the last twelve months. A side letter obligation you almost missed, a close that dragged, a capital call that went out with an error."**

From `us_gtm.md` §4.1 step 3. Ask it, then stop talking. The silence is the technique.

**What to listen for, because the whole screen hangs off the answer:**

| If they describe… | You have learned |
|---|---|
| A specific incident with a date and a name | Real pain, recent, remembered. This is a qualified conversation |
| A generic complaint ("Excel is painful") | No triggering event. Amber — probe for a specific instance once, then move on |
| "Honestly, nothing — it runs pretty smoothly" | Either it does, or they are not the person who feels it. Ask who *would* have a story. If nobody does, this is a red flag, not a small one |
| An incident that names a *person* who caught it | The control is a person, not a process. Best possible answer for us |

**Follow-ups, in this order:** *What did it cost to fix? Who found it? What changed afterwards?* The third question is the most revealing — "nothing changed" means the pain is tolerated, and tolerated pain does not get budget.

---

## 4. The §1.1 screen — six questions, woven in

Do not run these as a list. Each is a natural follow-on from the anchor answer. Target: about 15 minutes for all six.

### Q1 — Vehicles and structure *(verifies the non-negotiable qualifier)*

> "I counted {{VehicleCount}} vehicles in the filings. Is that still right, and is there anything alongside them that doesn't show up there — co-invest vehicles, an AIV, anything set up for a single deal?"

**Testing:** 3+ vehicles including at least one SPV or parallel fund — the one §1.1 calls non-negotiable, and the one ADV can only guess at (see [`adv_field_mapping.md`](adv_field_mapping.md) §5.1–5.2).

- ✅ **Green:** 3+ confirmed, at least one is a co-invest, SPV, parallel or AIV
- ⚠️ **Amber:** 3+ vehicles, all plain vanilla, all same jurisdiction, all same structure
- ❌ **Red:** fewer than 3 active vehicles

*Listen for the aside.* "Oh, and there's the 2022 deal vehicle we still have to report on" is the qualifier, and it will arrive as a throwaway.

### Q2 — Where the vehicle work lands

> "When you add a vehicle, what does that actually cost you in practice — does it fit the existing process, or does it need its own?"

**Testing:** the linear-headcount pain, and whether their structure has already outgrown their tooling. Not a §1.1 qualifier, but the single best predictor of whether they will buy anything at all.

### Q3 — LP base

> "Roughly how many distinct investors across all of it? I can see the per-fund numbers but not how much overlap there is."

**Testing:** 150–400 LPs. This phrasing is important — it tells them you read the filings *and* that you understand why the filed number does not answer the question (Q13 sums double-count re-upping LPs; see `adv_field_mapping.md` §4).

- ✅ **Green:** 150–400 distinct
- ⚠️ **Amber:** 100–150, or 400–600 with a clear growth path
- ❌ **Red:** under ~80 (too little servicing pain), or over ~800 (out of the first-5 profile and into a longer cycle)

### Q4 — Side letters *(the qualifier ADV cannot see at all)*

> "How many active side letters are you carrying across the vehicles — and where does that number live? Is there a list, or is it whoever negotiated them?"

**Testing:** the "10+ active side letters" complexity signal. This is the highest-value question in the whole screen precisely because it is unanswerable from public data.

- ✅ **Green:** 10+, and the honest answer about where they live is "a spreadsheet" or "Marcus knows"
- ⚠️ **Amber:** fewer than 10 but growing, or 10+ with a genuinely maintained obligation register
- ❌ **Red for this signal only:** almost none, and none expected — check whether another §1.1 complexity signal carries instead

*They only need **one** of the four complexity signals, so a red here is not a red for the account.*

### Q5 — Currency and carry

> "Does everything run in dollars, or do you have vehicles that don't? And on carry — is it whole-fund, or does it work deal by deal on any of them?"

**Testing:** the multi-currency and deal-by-deal-carry complexity signals. Both are invisible in Form ADV Part 1A (`adv_field_mapping.md` §5.3, §6.3), so this is the only place they get answered.

Deal-by-deal carry is a strong signal on its own: it means the carry calculation is per-vehicle and per-deal, which is exactly the thing GPs report having to simplify to fit their software.

### Q6 — Systems and the admin boundary

> "Who's doing what today — is {{Admin}} producing the calculations, or are you? And where does their file stop and your team start?"

**Testing:** tech posture, and the shape of the wedge. This also surfaces the "we already have Juniper Square / Allvue / Dynamo" reality early, which is far better known at minute 20 than at week 6.

- ✅ **Green:** already SaaS-native, several tools in use, can name them, describes the gaps *between* them
- ⚠️ **Amber:** one incumbent platform they are broadly happy with
- ❌ **Red:** "we don't really use software for this" — this is the price-sensitive, unsophisticated profile `us_gtm.md` §2.1 explicitly says not to pursue

---

## 5. The stakeholder question

§1.1 puts a ceiling of **≤4 in the buying group** and calls it "the one variable that can be screened for on a discovery call." It is also the question most likely to sound like a procurement interrogation, because the natural phrasing — "who are the decision makers and what is your approval process?" — is literally a sales-qualification script and every buyer recognises it.

**The fix is to make it a question about *your* work, not about their org chart.**

### Recommended phrasing

> "If this goes anywhere, I'd want to put the right things in front of the right people early rather than drip-feed it. Who'd need to be in the room — and is there anyone whose questions I should be answering up front rather than waiting to be asked?"

**Why this works:**

- The stated motive is *doing more preparation*, not *checking their authority*. That is also genuinely true — `us_gtm_zero_budget_notes.md` §7 and §8 both turn on volunteering the security pack before it is requested.
- "Who'd need to be in the room" gets a list of people. "Whose questions should I be answering up front" gets the *shape* — you learn there is a GC who will ask about AI, or a CTO who will ask about the API, or nobody.
- It invites them to hand you work, which people like doing.
- It is answerable in one breath. A procurement question is not.

### Alternative phrasings, by situation

| Situation | Phrasing |
|---|---|
| They mentioned a past vendor evaluation | "When you looked at {{PriorVendor}}, who else got pulled in? I'd rather know now than surprise someone at week six." |
| Small firm, dual-hatted CFO/CCO | "Is this basically your call and one other person's, or does it go wider?" — blunt is fine when the answer is obviously "two of us" |
| They are clearly not the decision-maker | "Is this something you'd take forward internally, or would you want me talking to someone else directly?" |
| Late in the call, nothing surfaced | "Last one — anything that would make this harder internally that I should know about now?" Often produces the InfoSec answer for free |

### Reading the answer

| Answer | Read | Action |
|---|---|---|
| Names 2–3 people, no process described | ✅ 8–14 week cycle. The §1.1 profile | Proceed |
| Names 4, one is a GC or CTO | ✅ At the ceiling. Volunteer the security answers now | Proceed, front-load |
| "It'd go through our vendor review" | ⚠️ Formal evaluation. That is the $3B+ motion (§1.1: 12–24 weeks) | Proceed only if everything else is strong |
| "InfoSec would need to do a full review" | ⚠️⚠️ Likely a SOC 2 gate. We do not have it, and `website_todos.md` says any SOC 2 claim is currently unverified | See §7 |
| Names 6+ people | ❌ Out of profile | See §7 |
| Deflects entirely | ⚠️ Either early-stage interest or not the buyer. Ask once more at the end, differently | — |

**Never ask about budget on this call.** §1.1 screens on complexity and stakeholders, not on stated budget, and a budget question converts a peer conversation into a sales call in one sentence. Budget is a pilot-stage conversation.

---

## 6. Close the call — 3 minutes

> "That was useful, thank you. Two things I could do from here, and you should pick zero, one or both:
>
> One — I configure an environment with your vehicles as they actually are, {{their structure in their words}}, and we walk one real scenario through it. Takes me a few days; costs you nothing until you're looking at it.
>
> Two — I send you the security answers and the data processing agreement now, so if this does go further your GC isn't the bottleneck.
>
> Or if this isn't a fit, say so and I'll stop — genuinely no hard feelings."

Three reasons this close is shaped this way: the configure-first offer is the COO win trigger (`us_gtm.md` §4.1 step 4); volunteering the security pack pre-empts the unspoken "unknown offshore vendor" objection (`us_gtm_zero_budget_notes.md` §8); and explicitly offering the exit is what makes the "no" arrive now instead of in six weeks of unanswered follow-ups.

**Do not offer a demo of anything not built.** If they ask for a compliance evidence binder, K-1 delivery, bank verification, SSO or a closing room, say it is not built and say when honestly, or say you do not know. This buyer checks.

---

## 7. Disqualification — when to walk away

**This is the section that protects founder capacity. Apply it the same day as the call, in writing, before enthusiasm decays into an open loop.**

### Hard disqualifiers — stop the same day, no nurture sequence

| Trigger | Why |
|---|---|
| **Fewer than 3 active vehicles, with none planned** | §1.1 calls this non-negotiable. Our differentiation is structural complexity; without it we are competing on features against incumbents with references |
| **6+ people in the buying group, or a formal vendor evaluation process** | That is a 12–24 week cycle needing a US reference and SOC 2. Per §1.1 this burns the highest-value list on the weakest version of the pitch |
| **A formal InfoSec review is mandatory** | We have no verified SOC 2 and, per `website_todos.md`, no verified attestation of any kind. No amount of sales work gets around it |
| **RAUM above ~$3B** | §1.1 hard cap. Log it for the post-SOC-2 list; do not work it now |
| **"We don't really use software for this"** | `us_gtm.md` §2.1: do not pursue unsophisticated or primarily price-sensitive buyers; they drain implementation resources without yielding reference value |
| **No pain surfaced on the anchor question, and nobody at the firm has a story** | Nothing to sell against. Tolerated pain does not get budget |
| **Mid-migration to another platform** | Wrong moment. Diarise 12 months and move on |
| **They ask for something we have to overclaim to win** | Losing honestly costs one deal. Overclaiming costs the market — §1 of the zero-budget notes is explicit that fund CFOs are a small, talkative community |

### Soft disqualifiers — two or more means stop

- Zero of the four §1.1 complexity signals present (no foreign LPs >25%, no 10+ side letters, no multi-currency, no deal-by-deal carry)
- Under ~80 distinct LPs
- Cannot name a single operational incident from the last 12 months
- Genuinely happy with an incumbent and cannot describe a gap
- Contact is neither a decision-maker nor willing to name one
- Reschedules twice without engaging
- Wants free pilot terms in the first conversation (`us_gtm.md` §4.4 step 5: a structured *paid* pilot; a free trial signals low confidence on both sides)

### Hold, do not kill

Some accounts are right and early. Move them to a light list — one touch per quarter, tied to a real event (a new fund close, a new Form D, a published guide). No sequence.

- Right profile, wrong timing (mid-audit, mid-raise, key hire pending)
- Right profile, ≤4 stakeholders, but wants a US reference customer — genuinely revisit after customer #1
- $3–10B firm with a warm introduction attached — §1.1's stated exception; take the intro, do not build a motion around it

### The founder-time rule

**No account gets more than 3 hours of founder time before it has produced either a second meeting with a second person, or an explicit next step with a date.** Configure-first demos are the main way this rule gets broken, because they feel productive. Cap the configure-first offer at a fixed number of accounts per week (§ `sequences/coo_operations.md`, email 3 notes) and honour every one you make.

---

## 8. Post-call — 10 minutes, same day

Write these down while they are accurate. They are the input to the ADV filter's next iteration and to [`message_testing_plan.md`](message_testing_plan.md).

| Field | Notes |
|---|---|
| Anchor-question answer, verbatim where possible | This is the demo spec and the follow-up email's opening line |
| Vehicle count and structure **as confirmed**, vs. what ADV said | If ADV was wrong, the filter needs to know why |
| Distinct LP count | The one number the filter can never get right |
| Which §1.1 complexity signals confirmed | Side letters, currency, carry, foreign LPs |
| Stakeholder count and names | Against the ≤4 ceiling |
| Fund admin, and where the boundary sits | |
| Incumbent systems named | Competitive intelligence the ads plan cannot buy |
| **Verdict: proceed / hold / disqualify, and the reason** | The reason field is mandatory. A disqualification without a recorded reason gets re-worked six weeks later by whoever forgot |
| Which sequence and which hook produced this meeting | Feeds the test readout |

**Feed the filter.** When five calls disagree with the ADV row in the same direction — vehicle counts consistently higher, LP counts consistently lower, "SPV" heuristic consistently wrong — that is a filter bug, and fixing it is worth more than another 100 sends.
