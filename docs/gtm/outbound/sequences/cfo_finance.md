# Sequence — CFO / Head of Finance

**Read [`README.md`](README.md) first.** The approved-claim list and the verified-link list are binding.

**Persona** (`us_gtm.md` §2.2, persona 2). Title variants: CFO, Managing Director Finance, Head of Fund Finance. Owns financial controls, audit readiness, the fund admin relationship, tax compliance.

**Stated pain:** compliance evidence assembled manually before every audit or LP due-diligence review; bank instruction changes create fraud risk that is not systematically controlled; K-1 and tax form tracking is spreadsheet-managed.

**Stated win trigger:** compliance evidence binder demo + bank instruction change control workflow.

> ### ⚠️ The stated win trigger cannot be demoed today
>
> Both halves of it are roadmap: the compliance evidence binder has no code, and bank instruction change control, dual approval and Plaid verification do not exist. **This sequence therefore does not chase that trigger.** It works the same underlying anxiety — *money moves and the number has to be defensible afterwards* — through what is actually shipped: the pre-flight gates on calls and distributions, and the allocation engine's stored formula-plus-inputs.
>
> This is flagged to the orchestrator in `../PROGRESS.md`. It is a real gap between the GTM plan and the product, not a copywriting choice.

**Arc:** the wire that shouldn't have gone out → where the number came from → consolidating across vehicles that don't share a currency → close.

---

## Email 1 — the pre-wire problem

**Subject line variants** (pick one per test cell, hold it constant — see `../message_testing_plan.md`):

- A. `before the wire goes out`
- B. `who checks the distribution file`
- C. `{{FundName}} distributions`

**Body** — 84 words with hook variant 1.

```
{{FirstName}} —

{{Hook}}

Nobody wires the wrong amount out of carelessness. It happens because
the checklist that catches it lives in one person's head, and that
person was on leave the week of the close.

Wrote up the five things that have to be true before a distribution
leaves the building:
https://caphive.com/distribution-readiness.html

Is that check written down at your end, or is it someone's habit?

{{SenderName}}
```

**Hook variants** — use the one the ADV row licenses, per `../personalization_framework.md` §3:

1. *Self-administered (Q26(a) = No):* "{{Firm}} looks to be administering the funds in-house rather than through a third party, which means the payment file and the check on the payment file are produced by the same team."
2. *Named administrator (Q26(b)):* "You're with {{Admin}}, so the calculation isn't the question — what happens on your side between their file and the wire usually is."
3. *Multiple vehicles (`pf_count_effective` ≥ 4):* "Running {{VehicleCount}} vehicles means {{VehicleCount}} distribution cycles a year that each have to be right the first time."

**Notes.** The closing question is deliberately answerable in one line and is genuinely diagnostic — "it's written down" and "it's Sarah" are different conversations. Do not upgrade "bank details present" to "bank details verified" anywhere in this email; verification is not built.

---

## Email 2 — where the number came from

**Subject variants:**

- A. `six months later`
- B. `how that number was derived`
- C. `audit question`

**Body** — 71 words.

```
Following up on the note below.

The version of this that costs the most isn't the wrong number. It's
the right number, six months later, when the auditor or an LP asks how
it was derived — and the workbook that produced it has been saved over
four times since.

We store the formula and the actual input values against every
generated figure, so the derivation survives the quarter:
https://caphive.com/allocation-engine.html

{{SenderName}}
```

**Notes.** This is the closest shipped analogue to the persona's "audit readiness" pain, and it is a *verified* claim — the allocation engine stores formula and inputs per generated number. Do not extend it to "audit-ready binder" or "SEC exam evidence pack".

---

## Email 3 — switch the hook, switch the problem

**Subject variants:**

- A. `one number across {{VehicleCount}} vehicles`
- B. `consolidating {{FundA}} and the offshore side`
- C. `different currencies, one report`

**Body** — 74 words. Use this variant only when the ADV row supports it (a non-US Q2 jurisdiction, or Q16 above 25%, or a named offshore sibling).

```
Last one on this thread, {{FirstName}}.

{{ReserveHook}}

Two vehicles that don't share a jurisdiction — and often don't share a
currency — still have to produce one performance figure that agrees.
Most firms do that restatement by hand in a workbook, at a rate someone
picked on the day.

Each record converts at the rate on its own economic date, so the
consolidated view doesn't drift:
https://caphive.com/tracking-currency.html

{{SenderName}}
```

**Reserve hook variants:**

1. *Offshore parallel/feeder:* "The other thing I noticed — {{FundA}} in Delaware with what looks like a {{Jurisdiction}} sibling alongside it."
2. *High non-US ownership:* "{{FundName}} looks to be around {{NonUSPct}}% non-US by beneficial ownership."
3. *Master-feeder:* "{{FeederName}} feeding {{MasterName}} means the allocation lands at the master and has to be attributed back down."

**If the account has no cross-border signal**, substitute this body instead — 68 words:

```
Last one on this thread, {{FirstName}}.

The call notice is the other one worth having a control on. It's a
legal instruction to move money, and every fund I've spoken to has
retracted one at some point.

Same idea as the distribution check, at the front of the cycle — KYC,
notice generated, documents approved, notifications configured, in that
order, stopping at the first failure:
https://caphive.com/capital-call-notices.html

{{SenderName}}
```

---

## Email 4 — close the loop

**Subject variants:**

- A. `closing this out`
- B. `wrong person?`
- C. `last one`

**Body** — 38 words.

```
{{FirstName}} — I'll stop here.

If this sits with someone else on the operations side, I'd rather send
it to them than keep landing in your inbox. Either way, no reply needed.

{{SenderName}}
```

**Notes.** "Wrong person?" is the highest-yield email in most sequences and it doubles as intelligence: a redirect names the real buyer and tells you the buying group's shape, which feeds the ≤4-stakeholder screen. It is also honest — we genuinely would rather email the right person. Do not add a "final chance" or a discount; both read as retail.

---

## Reply handling

| Reply | Response |
|---|---|
| "Send me more" | Do **not** send a deck. One paragraph plus a second link from the verified list, and a booking link if A3 is live |
| "We use {{Admin}}" | "Good — this isn't a replacement for them. Where does their file stop and your team start?" That question opens the discovery call |
| "We're happy with our current setup" | One question, then stop: "Fair enough — out of interest, who reconciles the close percentages when a vehicle admits late?" |
| "Not the right person" | Thank, ask for the name, stop the sequence, start the correct persona's sequence fresh |
| Anything about security | Answer directly and do **not** link the security page (see `README.md` §3). Say what is true: encryption in transit and at rest, per-user access control, full audit trail, 2FA. **Do not claim SOC 2 or ISO 27001** |
| A pricing question | `https://caphive.com/pricing.html`. Do not quote a number in email |
