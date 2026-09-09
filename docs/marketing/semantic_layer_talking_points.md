# Semantic Layer — Field Guide for Marketing & Sales

```yaml
subject: CapHive MCP semantic layer (app/packs/ai/mcp_server/ontology/)
format: Sales & marketing enablement — positioning, objections, approved copy
audience: Marketing, SDRs, AEs; technical evaluators via section 05
source_article: website_src/pages/semantic-layer.html (caphive.com/semantic-layer.html)
published_artifact: https://claude.ai/code/artifact/51ca79fa-567b-4d2d-bcdd-bca0fd493ffd
figures_verified: >
  All figures measured from the codebase and the drift-guard test on 2026-09-08:
  16 ontology files, 22 registered tools, 1,414 filter conditions + 314 sort
  options = 1,728 rules executed against the live schema per build, 0 advertised
  fields the database silently ignores.
compliance_note: >
  Never claim "accurate answers", "guarantees correctness" or "eliminates
  hallucination" — see section 08. Accuracy is claimable only as a CLOSED CLASS
  of error (dropped filter, ignored sort, mixed currencies). Do NOT reference
  defects found while building the semantic layer, in any channel — the point
  lands on what the build check prevents, not on what it once caught.
  No client or fund named anywhere; examples use "Fund II" and illustrative figures.
tool_count_note: >
  RESOLVED AND CORRECTED (2026-09-08). Earlier collateral said 23 read-only
  tools. That counted 23 *_tool.rb files, one of which is
  application_mcp_tool.rb — the abstract base class, not a tool.
  McpController#authorized_tools registers 22. The correct public figure is 22,
  and it has been corrected in the blog article, its source draft and build
  script, both MCP user guides, and the product design docs.
```

---

## 01 — Positioning

Three nested versions. Use the shortest that fits the moment.

**The one line.** *We make sure the AI refuses, instead of guessing.*
For a bio, a booth banner, the first line of a cold email.

**The one paragraph.** Anyone can connect an AI assistant to fund data. The hard part is that
when the assistant asks for something the data can't answer, most systems quietly ignore the
bit they didn't understand and return a real number for the wrong set of records. CapHive
writes down what every field and measure actually means, and generates the AI's entire
interface from that definition — so a question we can't answer correctly gets refused, not
guessed.

**The one minute.** Open with the failure — *"what did Fund II pay in management fees?"*
returning the total for all six funds, with no error. Land that it isn't hallucination and a
better model won't fix it. Then: we defined 16 entities, generated the AI interface from
those definitions, and re-test 1,728 rules against the live database on every release. Close
on the refusal — the assistant now says what it can't answer and why.

---

## 02 — The narrative: five beats, in this order

The order matters more than the words. Beat 2 changes how they think; beat 3 stops them
reaching for their existing answer. Don't skip to the product.

1. **The risk isn't what they think it is.** Every buyer arrives worried about the AI making
   things up. That's the wrong worry, and saying so buys you the rest of the conversation.
   > "The number that will hurt you isn't invented. It's real — it just answers a question
   > nobody asked."

2. **Show the mechanism, don't assert it.** A query layer doesn't reject a filter it can't
   honour. It drops it and returns everything else. Successful response, valid data, wrong
   population.
   > "They asked about one fund. The system understood two of the three conditions and threw
   > the third away. Nothing errored."

3. **Close the two escape hatches.** They will reach for "a better model" or "we review the
   output". Neither works.
   > "You can't review your way out of this. The answer that's wrong looks exactly like the
   > answer that's right."

4. **The fix is written definitions, not a smarter bot.** Sixteen entity definitions holding
   every field, measure and rule; the AI's description, its options and the gate on every
   request are all generated from them, so they can't contradict each other.
   > "We wrote down what your data means, and the AI's whole interface is generated from that."

5. **Prove it stays true.** The differentiator and the strongest close. Anyone can write a
   document. We execute 1,728 rules against the live database every release, and a definition
   that has drifted stops the release.
   > "Ambiguity gets found by a build, or it gets found by an LP reading a wrong number. Those
   > are the only two options."

---

## 03 — Proof points

**Say it** = measured and defensible as-is. **Frame it** = true, but needs the given wording.

| Claim | Figure | Status | How to say it |
|---|---|---|---|
| Entities defined | 16 | Say it | Funds, commitments, calls, remittances, distributions, payments, ledger, units, companies, investments, valuations, KPIs, documents, cap table. |
| Tools governed | 22 | Say it | "22 read-only tools". Older assets said 23 (they counted the abstract base class) and have been corrected. |
| Rules re-verified per build | 1,728 | Say it | 1,414 filter conditions plus 314 sort options, executed against the live database on every release. Both sub-figures are quotable. |
| Fields the database silently ignores | 0 | Say it | The headline stat. Every field we advertise is proven to actually filter, every build. |
| Write access | None | Say it | "No write tool exists" is stronger than "writes are disabled", and it is the true statement. |
| Assistants supported | Claude · ChatGPT · Gemini | Say it | Plus anything speaking the Model Context Protocol. Lead with "bring your own AI". |
| Permissions | Unchanged | Say it | Every request runs in the asking person's own scope; gated by role and named client app; every call logged. |
| Accuracy | — | Frame it | Never claim correct answers. Claim a closed *class* of error: the filter that was ignored, the sort that was dropped, the currencies that were added together. |

---

## 04 — Objections

Answer in two moves: agree with the part that's true, then show why it doesn't reach this
problem. Arguing with the premise loses the room.

**"Every vendor says they've solved AI accuracy."**
Agree, then narrow. *"Most of them are solving hallucination. We're solving a different failure
— the one where the model doesn't invent anything and the answer is still wrong."* Then give
them the separating question: *ask them what happens when the assistant filters on a field that
doesn't exist.* If the answer isn't "it errors", it silently returns everything.

**"Isn't this just prompt engineering?"**
*"A prompt is advice the model may follow. Two of our three checks don't depend on the model
cooperating at all."* The options are enumerated in the schema, so an invalid one can't be
composed; anything that arrives anyway is refused before it reaches the database.

**"Our team reviews anything that goes to an investor."**
Never dismiss this. *"Review catches an answer that looks wrong. This one looks exactly right."*
If they push: four decades of human-factors work on automation bias says confident,
well-formatted automated output gets verified *less*, not more.

**"We'd never let AI near investor data."**
Reframe from permission to path. *"Someone on your team already pasted a fund export into
ChatGPT this quarter. The question isn't whether it happens — it's whether it happens somewhere
you can audit."* Then the governance facts.

**"Won't a better model make this unnecessary?"**
*"A better model reasons better about what it's given. It can't know that a third of its
question was discarded before the data came back."* The information needed to catch it was
never in the response.

**"We already have a BI semantic layer."**
Credit it, then find the gap. *"Good — you're halfway there. A BI layer assumes a person picked
the filters and will notice a chart that looks off."* Neither assumption survives when the
consumer is a model composing its own queries.

**"Who decides what 'outstanding' means — you or us?"**
Always: *"You do."* We ship definitions for the whole platform so nothing is required to start,
and your conventions override ours. This is often where a deal turns — most firms find two teams
have been answering the same question two different ways.

**"Sounds like a lot of maintenance."**
*"It maintains itself, loudly. If a definition stops matching the database, the release stops."*
The failure mode of an unmaintained document is silent wrongness. Ours is a build that won't ship.

---

## 05 — By audience

| Persona | Lead with | Hook |
|---|---|---|
| **CFO / Finance director** | Signature risk. The wrong fee total reaching a board pack; the control sits before the answer exists, not in review. | "Would you sign a number your assistant produced in eleven seconds?" |
| **COO / Head of fund ops** | Definitional consistency. They already arbitrate what "called" and "outstanding" mean; the definition exercise is valuable on its own. | "Two of your teams define DPI differently. Want to find out which?" |
| **Head of IR / LP relations** | What reaches the investor. Emphasise refusal over a filled gap. | "The worst outcome isn't 'I don't know.' It's a confident figure you have to walk back." |
| **IT / Security / technical evaluator** | Architecture. Generated schema and validator from one versioned source; contracts executed in CI; MCP over OAuth with dynamic client registration and PKCE; per-request authorisation; no write path. | "There's no credential to rotate, because none is issued." |

---

## 06 — Approved copy

Written to the claims in section 03. If you change a number, check it there first.

**LinkedIn post opener**

> An AI assistant connected to your fund data will never tell you it misunderstood the question.
>
> Ask it what one fund paid in management fees, and if the system doesn't recognise the fund
> filter, it quietly drops it and answers for all of them. Real number. Correct arithmetic. Wrong
> set of records. No error.
>
> This isn't hallucination. A better model won't fix it, and neither will a human reviewing the
> answer — because the answer that's wrong looks exactly like the answer that's right.

**Cold email, first two lines**

> Most AI-on-your-fund-data demos show the assistant answering correctly. The more useful
> question is what it does when it can't.
>
> Ours refuses — and names the field it needed. Worth 20 minutes?

**Website / deck subhead**

> Sixteen entities defined. 1,728 rules re-tested against the live database on every release.
> Zero fields the database silently ignores.

**Conference or booth line**

> Ask your current vendor what happens when the AI filters on a field that doesn't exist. If the
> answer isn't "it errors," it's returning everything.

**Webinar / session titles**

- The number was right. The question wasn't.
- Why your AI will never tell you it misunderstood
- Grounding isn't enough: what happens after retrieval goes wrong

**Boilerplate paragraph**

> CapHive's semantic layer defines what every field and measure in a fund platform means —
> currency basis, approval state, gross versus net — and generates the entire AI interface from
> those definitions. Requests that can't be answered correctly are refused rather than guessed,
> and every definition is re-verified against the live database on each release.

---

## 07 — The 60-second demo

Don't demo the assistant answering well — every competitor can do that. **Demo the refusal.**
It is the only moment in the category a prospect hasn't already seen.

1. **Ask a good question, get a good answer.** Fifteen seconds. Gets the "fine, so does
   everyone's" out of the way early.
2. **Ask for something that isn't there.** Filter on a field the data doesn't have. The
   assistant comes back naming the right field instead of returning a number.
   > "Watch what it does with a question it can't answer."
3. **Let it correct itself.** It re-asks with the correct field and answers properly. The
   refusal wasn't a dead end, it was a correction.
4. **Ask the cross-currency question.** "Total committed across all funds." It comes back split
   by currency, and says why. Close there.
   > "Every other system I've seen adds those together."

---

## 08 — Language

Each item on the right is a claim a technical evaluator can disprove in a meeting, and one
disproved claim costs you the other twenty.

| Use | Avoid |
|---|---|
| "Refuses rather than guesses" — the whole product in three words | "Guarantees accurate answers" — we don't and can't |
| "A real number for the wrong question" — the failure, precisely | "Eliminates hallucination" — different problem; claiming it signals we don't understand ours |
| "No write tool exists" — stronger and truer than "writes are disabled" | "AI-powered" as the value — the value is the governance |
| "Re-verified every release" — competitors can't match this with a document | "Enterprise-grade", "bank-grade" — unfalsifiable, reads as filler |
| "Your definitions" — ownership sells, and it's accurate | Naming a competitor as broken — describe the failure, let them test for it |
| "Bring your own AI" — Claude, ChatGPT, Gemini, no lock-in | "Certified" or "audited" about the semantic layer — it's *tested*, a different word |
| "Closes a class of error" — specific, provable, defensible | "Zero errors" — the defensible zero is *fields the database silently ignores* |
| "Every definition is re-tested against the live database each release" — the mechanism | Any reference to defects found while building it — the story is what the check prevents, not what it caught |

---

## Action items before anything ships

- [x] Correct the tool count from 23 to 22 across the article, its source draft and build
      script, both MCP user guides and the product design docs. Site rebuilt.
- [ ] Have someone verify the academic citations in the long-form article (author, venue, year).
      They are quoted qualitatively with no benchmark percentages, but this is customer-facing.
- [x] Decided: defects found while building the semantic layer are not referenced in any
      marketing or sales material. Removed from this guide.
