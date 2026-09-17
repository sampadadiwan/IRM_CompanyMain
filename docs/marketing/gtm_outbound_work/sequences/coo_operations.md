# Sequence — COO / Head of Operations

**Read [`README.md`](README.md) first.** The approved-claim list and the verified-link list are binding.

**Persona** (`us_gtm.md` §2.2, persona 1 — the primary champion). Title variants: COO, VP Operations, Head of Fund Operations. Owns onboarding, capital calls, distributions, compliance workflow, fund admin coordination.

**Stated pain:** their team performs high-value operational work that should be automated; errors in manual processes create expensive downstream corrections; **each new fund vehicle adds linear headcount instead of leveraging existing infrastructure.**

**What they want to hear:** "CapHive handles the operational complexity your current stack cannot — without requiring you to simplify your fund structure."

**Stated win trigger:** a demo configured against their actual fund structure — parallel vehicles, co-invest SPVs, mixed investor types — handled without workarounds.

**Stated objection:** "We've tried other platforms and they couldn't handle our complexity."

> **This is the only persona whose win trigger is fully reachable today**, and the sequence is built to reach it. Email 3 is not a pitch; it is an offer to pre-configure their structure before any call. That offer is free, it is the deal moment per `us_gtm.md` §4.1 step 4, and it is the strongest asset in this whole document. Master-feeder is genuinely modelled in the data model, so the offer is not a bluff. Parallel funds and SPVs are separate fund records grouped under a parent entity rather than a typed structure — **which is fine to demo and wrong to describe as "SPV support"**.

**Arc:** the linear-headcount problem → the onboarding drag that delays the close → *"let me build your structure before we talk"* → close.

---

## Email 1 — the vehicle that added a person

**Subject line variants:**

- A. `vehicle {{VehicleCount}}`
- B. `the headcount question`
- C. `adding a fund, adding a person`

**Body** — 88 words with hook variant 1.

```
{{FirstName}} —

{{Hook}}

The pattern I keep running into: the first three vehicles fit the
process, and every one after that adds a person rather than a
percentage. Not because the work is hard — because the coordination
doesn't compress. Same close mechanics, different rates, different
documents, different investor lists.

Wrote about where that actually breaks — the allocation, and every
number carrying its own receipt:
https://caphive.com/allocation-engine.html

Is that roughly your experience, or has it scaled better than that?

{{SenderName}}
```

**Hook variants:**

1. *Vehicle count (`pf_count_effective` ≥ 4):* "{{Firm}} looks to be running {{VehicleCount}} vehicles across the current filings."
2. *Likely SPV alongside a flagship:* "Alongside {{FundA}} you've got what looks like a smaller vehicle on the side — usually the one that doesn't fit the process built for the flagship."
3. *Master-feeder:* "{{FeederName}} feeding {{MasterName}} — so one commitment, two sets of mechanics."
4. *Self-administered (Q26(a) = No):* "Administering in-house rather than through a third party means the whole cycle is your team's, every vehicle, every time."

**Notes.** The closing question invites a correction, which is the point — a COO who replies "actually we've handled that fine" has still replied, and has told you their structure. Do not claim "handles any structure"; that is the exact sentence the objection is armed against.

---

## Email 2 — the drag at the front of the cycle

**Subject variants:**

- A. `onboarding drag`
- B. `retyping the passport`
- C. `where the close slips`

**Body** — 74 words.

```
Following up on the note below.

The other place headcount goes is the front of the cycle. Investors
abandon a form that asks them to retype what's already on the document
they just uploaded, and then someone on your side chases them for three
weeks while the close slips.

Inverting it — read the documents first, pre-fill, ask them to confirm
— is a time-to-close story rather than an efficiency one:
https://caphive.com/document-first-kyc.html

{{SenderName}}
```

**Notes.** The second agent auditing the finished record for completeness and expiry is what makes this credible to an operations buyer rather than sounding like OCR — hold it for the call, it is too much for email 2. **Do not mention Persona, Middesk, ComplyAdvantage or any named KYC provider**: those are integration targets, not wired.

---

## Email 3 — the offer (this is the important one)

**Subject variants:**

- A. `build your structure first`
- B. `{{FundA}} and the offshore side, configured`
- C. `before any call`

**Body** — 74 words.

```
{{FirstName}} — different approach.

Every platform demo you've sat through used a clean ten-investor fund,
and you've watched at least one of them fall over on your actual
structure afterwards.

So: before any call, I'll configure an environment with your vehicles
as they actually are — {{StructureSummary}} — and walk one real
scenario through it. If it doesn't hold up, that's a useful thirty
minutes for both of us.

Worth doing?

{{SenderName}}
```

**`{{StructureSummary}}`** — 6 to 12 words, assembled from the ADV row, using **fund names exactly as filed**. Examples of the right shape:

- "Fund IV, the offshore parallel, and the co-invest vehicle"
- "three vintages running concurrently and a master-feeder on the newest"
- "{{MasterName}} with its feeder, plus the two smaller vehicles alongside"

**Notes.** This email carries no link and no proof asset by design — the offer *is* the proof. It directly answers the "they couldn't handle our complexity" objection by proposing the test rather than denying the premise.

**Two honesty constraints on the offer:**

1. **It must actually be honoured.** `us_gtm_zero_budget_notes.md` §9 budgets ~2 hrs/week for meetings and demos in Phase 0–1. Configuring a structure takes real time. If the founder cannot honour every acceptance, cap this email to a defined number of accounts per week rather than offering it to everyone. An unhonoured offer is worse than no offer.
2. **Describe what you will build in their vocabulary, not ours.** "Your co-invest vehicle" is a description of their world. "SPV support" is a product claim we cannot make — parallel and co-invest vehicles are separate fund records grouped under a parent entity, not a typed structure with type-specific behaviour.

---

## Email 4 — close the loop

**Subject variants:**

- A. `closing this out`
- B. `wrong person?`
- C. `last one`

**Body** — 41 words.

```
{{FirstName}} — I'll leave it here.

If fund operations sits with someone else, I'd rather send this to them
than keep landing in your inbox. And if the answer is just "not now",
that's a fine answer. No reply needed.

{{SenderName}}
```

---

## Reply handling

| Reply | Response |
|---|---|
| "Yes, configure it" | **Drop everything and do it.** This is the win trigger. Ask only what ADV cannot tell you: investor types per vehicle, whether any vehicle admits late, and which recent situation to model. Then book the call *after* it's built |
| "We've tried platforms that couldn't handle our complexity" | Do not defend. Ask: "Which part broke?" Then configure exactly that part. This is the objection converting itself into the demo spec |
| "We use {{Admin}}" | "This isn't a replacement for them — it's what happens on your side before their file goes out. Where does the handoff sit today?" |
| "Send me a deck" | No deck. One paragraph, one link from the verified list, and repeat the configure-first offer — it is a stronger asset than any deck |
| Asks about a roadmap item (closing room, evidence binder, K-1s, SSO, bank verification) | **Say it is not built.** Give a real answer about what exists adjacent to it. A COO who catches an overclaim disqualifies the vendor permanently, and this persona will dig into exactly these edges |
| Asks who else uses it | No customer names are approved for attribution. Say so plainly and offer the configure-first demo as the substitute proof. Revisit once prerequisite D1/D2 land |
