# Sequence — Director of Investor Relations

**Read [`README.md`](README.md) first.** The approved-claim list and the verified-link list are binding.

**Persona** (`us_gtm.md` §2.2, persona 3). Title variants: IR Director, Head of IR, VP Investor Relations. Owns LP experience, capital call and distribution communications, reporting, tax-season coordination.

**Stated pain:** LP questions consume disproportionate IR team time; capital call and distribution processes require significant manual coordination; **side letter commitments create obligation risk that lives in someone's head**; tax season is a fire drill.

**Stated win trigger:** LP portal + AI investor service assistant + side letter obligation matrix.

> **Win-trigger status, honestly.** The side letter obligation matrix is **shipped** — extraction with the source clause, a mandatory counsel-review gate, then dated owned tasks — and it is the strongest thing we can put in front of this persona. The LP portal is **shipped**. The LP-facing AI assistant exists in code but has **no user guide** and unfunded commitment is specifically *not* surfaced in the portal, so **do not use the AI assistant or unfunded commitment as an email claim**. Tax season is a **roadmap** area (no Tax Center, no K-1 workflow) and is not touched anywhere in this sequence.
>
> Net: two thirds of this persona's win trigger is real. Lead with the side letters.

**Arc:** the obligation nobody owns → the LP question you answered four times this week → the review gate that makes it credible → close.

---

## Email 1 — the folder

**Subject line variants:**

- A. `side letters, and who owns them`
- B. `the obligation nobody owns`
- C. `after the LPA is signed`

**Body** — 87 words with hook variant 1.

```
{{FirstName}} —

{{Hook}}

The side letters are almost always fine. What isn't fine is that the
obligations inside them outlive the person who negotiated them —
a quarterly reporting commitment, a notice period, a co-invest right —
and they surface during an LP's re-up diligence rather than before it.

Nobody sells a tool for this, so it lives in a folder and in someone's
memory:
https://caphive.com/side-letter-obligations.html

How are yours tracked today — a spreadsheet, or a person?

{{SenderName}}
```

**Hook variants** — per `../personalization_framework.md` §3:

1. *Funds of funds on the register (Q15(a) > 0%):* "With funds of funds on the {{FundName}} register, you're almost certainly carrying side letters — institutions rarely come in without one."
2. *Placement agent (Q28(a) = Yes):* "A placement agent on {{FundName}} usually means an institutional LP base, which usually means side letters."
3. *Multiple vintages:* "{{VehicleCount}} vehicles means {{VehicleCount}} sets of side letters, and the older ones are the ones nobody has read recently."
4. *High non-US ownership (Q16 > 25%):* "{{FundName}} looks to be around {{NonUSPct}}% non-US by beneficial ownership — which usually means per-LP reporting variation on top of whatever was negotiated."

**Notes.** The closing question — "a spreadsheet, or a person?" — is the highest-reply-probability line in these three sequences, because both answers are slightly embarrassing and the honest one is "a person". Keep it.

---

## Email 2 — the same ten questions

**Subject variants:**

- A. `the same ten questions`
- B. `did they open it`
- C. `after every capital call`

**Body** — 73 words.

```
Following up on the note below.

The related one: after every capital event, the same ten LP questions
arrive, and answering them is a full day nobody planned for. Half of
them are really "did you send me that, and did I miss it?"

Every document records who opened it and when — which turns that
particular exchange into a lookup instead of a search through sent
mail:
https://caphive.com/lp-relationship-crm.html

{{SenderName}}
```

**Notes.** Document view tracking is verified and shipped, and it is an unusually concrete claim for a cold email. **Do not extend it into "LPs self-serve their unfunded commitment"** — that is specifically not surfaced in the portal. Do not mention an AI assistant.

---

## Email 3 — why it doesn't scare legal

**Subject variants:**

- A. `who approves the extraction`
- B. `counsel sees it first`
- C. `the part that makes it usable`

**Body** — 75 words.

```
Last one on this, {{FirstName}}.

The obvious objection to reading obligations out of side letters
automatically is that nobody's GC will accept a machine's
interpretation of a negotiated clause — and they're right.

So nothing becomes an obligation on its own. Each extracted item
carries the clause it came from, goes to counsel for review, and only
then becomes a dated task with an owner:
https://caphive.com/agent-side-letter-obligation.html

That review gate is usually what makes it usable at all.

{{SenderName}}
```

**Notes.** This is the strongest email in the three sequences, because it pre-empts the objection instead of waiting for it and it is entirely true — the review status genuinely defaults to pending and nothing auto-activates. It also arms the IR director for the conversation they will have to have with their GC, which is exactly what a champion needs. **Do not mention MFN**: an MFN flag exists, cross-side-letter comparison does not.

---

## Email 4 — close the loop

**Subject variants:**

- A. `closing this out`
- B. `wrong person?`
- C. `last one`

**Body** — 40 words.

```
{{FirstName}} — I'll stop here.

If side letter obligations sit with legal or operations rather than
IR at {{Firm}}, I'd rather send this to them than keep landing in your
inbox. No reply needed either way.

{{SenderName}}
```

**Notes.** For this persona the redirect is genuinely likely — side letter obligations often sit with the GC — and a redirect to the GC is a *good* outcome here, unlike a cold approach to the GC, because it arrives with an internal referral attached.

---

## Reply handling

| Reply | Response |
|---|---|
| "A spreadsheet" / "honestly, a person" | The opening. "How many side letters across the vehicles, roughly?" — that single number is the §1.1 complexity qualifier we cannot get from ADV (see `../adv_field_mapping.md` §6.1) |
| "Our GC handles that" | "Makes sense — would it help to show them the review gate? It's built so counsel approves before anything becomes an obligation." Loop the GC *by referral*, never cold |
| "We don't have many side letters" | Believe them and pivot once: "Then it's probably the LP question load instead — how much of a week goes on those after a call?" If that also lands flat, stop |
| Asks about tax season / K-1s | **Not built.** Say so. Offer what is true — secure document delivery with per-LP view tracking and external advisor access — and do not use the words "Tax Center" |
| Asks about the LP portal | Portal is real: per-investor scoped access, documents, capital activity, external advisor access. **Do not mention an AI assistant or unfunded-commitment self-service** |
| Asks about MFN | "There's a flag for MFN-relevant clauses. Cross-side-letter comparison isn't built." Say the second sentence |
