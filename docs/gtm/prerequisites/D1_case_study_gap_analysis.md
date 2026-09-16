# D1 — Case Study Gap Analysis and Customer Ask

**Checklist row:** D1 in [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md)
**Done when:** 2–3 written case studies with hard numbers, wording approved by the customer in writing.
**Status:** **BLOCKED-NEEDS-HUMAN.** Six case studies already exist and are good content marketing. **None of them satisfies D1**, and the gap cannot be closed by writing — it can only be closed by asking customers for three things. This document is the gap analysis and the ask.

**Nothing in §§1–6 invents a metric, a customer name, or a quote.** Every number in those sections is quoted from the existing pages as written.

> **Updated 2026-08-16 — read [§7](#7-decision-taken-2026-08-16--labelled-illustrative-composites) before acting on §§1–6.** Three pages now carry **modelled** before/after figures, labelled as such on the page. §7 records every assumption behind them, amends Rule 1 in §6, and notes the confirmed **US reference client**. D1 itself is still open: the §4 ask has not been sent, and no customer has approved anything in writing.
>
> **Also updated 2026-08-16 — [§8](#8-jurisdiction-pass-14-closed-2026-08-16) closes the §1.4 gap.** The jurisdiction rewrite described in §3 as "a bigger job than the other two combined" has been done. `case-investor-onboarding` is now US-readable and the §3 instruction *"do not link it from US outbound"* is **withdrawn**. §1.4's posture table below is superseded by §8.1.

---

## 1. Why six existing case studies still leave D1 at zero

The pages in `website_src/pages/case-*.html` are strong: specific, technically credible, written by someone who plainly knows fund operations. They do the §3.2 job of "content you link to instead of attaching a deck" well.

They fail D1 on four counts, and the fourth is the one that matters for a US buyer.

### 1.1 The customer is anonymous

The index states it outright: *"Client names are withheld. The workflows, the mechanics and the direction of travel are not."* Each page repeats a disclaimer that supporting detail is *"illustrative of how engagements of this shape run."*

That is honest, and it is fatal for the D1 purpose. An anonymous case study is a vendor claim with extra formatting. The whole reason `us_gtm_zero_budget_notes.md` §1 lists "Proof" as the first trust mechanism is that the buyer needs something they can verify without trusting us — and there is nothing here to verify.

### 1.2 No human is quoted, named, or titled

Across all six pages there are **zero** customer quotes. Every quotation-styled block is CapHive's own editorial voice. The schema.org `author` on all six is `{"@type":"Organization","name":"CapHive"}` — the markup correctly says these are articles we wrote about ourselves.

The only human names anywhere in the set are three **design placeholders** in a `hidden` testimonials block on the index (Theresa Webb, Arlene McCoy, Esther Howard), carrying the comment *"Hidden until real client quotes are ready: the names below are design placeholders from the old site."* **These must never be unhidden.** They are stock names from a template; publishing them would be fabricated testimony.

### 1.3 The metrics are scale and capability, not outcome

This is the precise gap. D1 asks for the shape *"quarter-close from 15 days to 4"* — a before number, an after number, same unit.

What exists instead:

| Metric as published | What it actually is |
|---|---|
| `200+ LPs onboarded digitally` | scale |
| `50+ portfolio companies on one reporting cycle` | scale |
| `100+ LPs drawn down per call` | scale |
| `500+ LPs served from one allocation run` | scale |
| `80+ transactions executed simultaneously`, `150+ agreements` | scale |
| `3 currency layers held simultaneously`, `8 documented rate-date rules` | capability |
| `0 KYC packs re-keyed`, `0 exchange rates guessed` | capability |
| `1 touch to generate an investor's document set` | capability |
| `A draft takes roughly 30–90 seconds` | product performance |

**Two pages carry literal `Before:` / `After:` headings** — `case-multi-currency-close.html` and `case-portfolio-reports.html` — and **neither contains a single number in either half.** They are qualitative narratives in outcome clothing, which is the most misleading possible arrangement: a skim reads them as proof and a close read finds nothing.

**One genuine improvement claim exists:** `case-investor-statements.html` states *"The operating team came out over 5× more efficient"* and *"Over 5× efficiency for the operating team."* Even this is a claimed multiple with **no baseline** — 5× of what, measured how, over which cycle. The same page states a before-state duration, *"the reason this fund's quarter used to take a fortnight,"* and then **never gives the after figure.** That is the closest thing on the site to a "15 days to 4" claim, and the second half of the sentence is simply missing. Recovering it is the single cheapest D1 win available.

One more precision issue worth fixing while asking: the index card says **`500+ LPs, 5× faster`** whereas the page says *"over 5× more efficient."* Efficiency and speed are not the same claim. Pick one and make both surfaces agree.

### 1.4 They read as India-domestic — to the exact buyer we are trying to reassure

`us_gtm_zero_budget_notes.md` §1 names the unspoken objection: *"too risky — an unknown India-based vendor with no US presence."* §8 says the entire de-risking strategy is to pre-empt it.

A US CFO clicking through from a cold email meets, in `case-investor-onboarding.html`: `AIF`, `SEBI-tagged form` with `investor category and sub-category`, `GIFT-tagged form carries IFSC declarations`, `PAN verification`, `CKYC returned a registry record from CERSAI`, `KRA answered from PAN and date of birth`, `Aadhaar or a digital signature certificate`, `e-stamping`, `stamp-paper configuration`.

Every one of those is accurate and none of them is a fault in the page. But as the proof asset attached to a US cold email, it is **evidence for the objection rather than against it.** It says: our customers are Indian funds with Indian regulatory workflows.

Jurisdiction ratings across the set:

| Case study | Jurisdiction posture | Notes |
|---|---|---|
| `case-portfolio-reports` | **Neutral** | No India-specific terms at all |
| `case-capital-drawdowns` | **Neutral** | Worked example is in `$`; no SEBI/PAN/Aadhaar |
| `case-investor-statements` | **Neutral** | Generic fund/folio currency, NAV, KYC |
| `case-multi-currency-close` | Light | `INR` appears once alongside EUR/GBP/USD; `10% NCD`, `CCDs` are Indian instrument types |
| `case-multi-party-transactions` | Light | `IFSC` bank detail, `Aadhaar or DSC`, `Where Indian stamping applies` |
| `case-investor-onboarding` | **Heavy** | Extensively SEBI/GIFT/PAN/CKYC/Aadhaar |

---

## 2. Per-case scorecard

Four columns: what it has, what is missing for D1, how hard the upgrade is, and whether it works for a US reader as-is.

| Case study | Already has | Missing for D1 | Upgrade cost | US-ready as-is? |
|---|---|---|---|---|
| **case-investor-statements** | The only improvement claim on the site (`over 5×`); a stated before-state (`a fortnight`); jurisdiction-neutral | The **after** number to pair with "a fortnight"; a baseline for the 5×; attribution; a quote | **Lowest** — one number and one permission | Yes |
| **case-capital-drawdowns** | Universal mechanics; `$` examples; the five-verb structure maps to any US GP | Any outcome number at all; attribution; a quote | Low–medium — needs a number that does not exist yet | Yes |
| **case-multi-currency-close** | Directly hits the §1.1 complexity qualifier (multi-currency); `Before:`/`After:` scaffolding already written | Numbers to put **inside** the existing Before/After; attribution; a quote | Low — the structure is already there and empty | Mostly — drop or generalise `NCD`/`CCD` |
| **case-portfolio-reports** | Jurisdiction-neutral; strong before-state narrative (`thirty reply within a fortnight`, `two send nothing`) | Numbers in the Before/After block; attribution; a quote | Medium | Yes |
| **case-multi-party-transactions** | `1 week` elapsed delivery is a real, checkable fact; genuinely impressive scale | No "before" to compare the week against; **the customer is never even described as a firm type** | Medium | Mostly — light IFSC/Aadhaar edits |
| **case-investor-onboarding** | Richest operational detail of the six | Outcome numbers; attribution; **and a US-readable version** | **Highest** — needs rewriting for jurisdiction, not just a number | **No** |

---

## 3. Which to upgrade first, and why

**Upgrade these two, in this order. Do not try to fix all six.**

**1. `case-investor-statements` — the fastest possible win.** It already claims an improvement and already states a before-state duration. It needs one number ("and now it takes ___"), one baseline for the 5×, and permission to attribute. It is jurisdiction-neutral, so it needs no rewriting. If only one asset gets upgraded, it is this one.

**2. `case-multi-currency-close` — the best strategic fit.** §1.1 makes multi-currency one of the four complexity signals that qualify a first-5 target. This page speaks directly to a qualifier we are screening for, so it is the natural link in Email 1 of the outbound sequence. Its `Before:`/`After:` block is already written and merely empty of numbers — the cheapest possible place to put a real figure. Generalise `10% NCD` and `CCDs converting to equity` to instrument-neutral language while you are in there.

**Deliberately not first: `case-investor-onboarding`.** It is the strongest page as writing and the weakest as a US proof asset. Fixing it means a jurisdiction rewrite, which is a bigger job than the other two combined, for an asset that will still lead with an Indian AIF. Leave it published for the India market; do not link it from US outbound.

**Deliberately not first: `case-multi-party-transactions`.** The `80+ deals in one week` fact is genuinely striking, but with no "before" it reads as scale rather than improvement, and the customer is never described even generically — a reader cannot tell what kind of firm this was. Ask for a firm descriptor when you ask the others; upgrade it third.

---

## 4. The customer ask — send this as written

Three things are needed from each customer, and they are separable: a customer who refuses naming may still give a descriptor and a number. **Ask for all three; accept any two.**

> **Blocking dependency (GTM doc §11):** it is unresolved whether current customers are usable as **US** references. That question should be answered by the same conversation, so it is built into the email below. If the answer is that they are India-only, D1 changes shape — the plan's §11 says the emphasis shifts from case studies to structured pilots, and the outbound sequence in [`C6_outbound_email_template.md`](C6_outbound_email_template.md) should drop its Email 3 rather than ship an unattributed proof point.

### Email to send

**Subject:** `A small ask — three things, about 20 minutes`

```
Hi <name>,

We are starting to talk to funds in the US, and the honest position is that we
can describe what CapHive does but we cannot yet point at a customer who will
say it. I would like to change that, and you are the first person I am asking.

Three things. Each is independent — a yes to one is useful even if the others
are a no.

1. ATTRIBUTION. May we name <firm> in a written case study? If that is not
   possible, would you be comfortable with a description instead — something
   like "a $1.2B venture fund with four vehicles"? Specific enough to be
   credible, not specific enough to identify you. Your call on the exact
   wording; we will not publish anything you have not approved in writing.

2. ONE NUMBER. The thing I most want is a before-and-after on something you
   measure. For example:
     - the quarter close: how many days did it take before, and how many now?
     - investor statements: how many people for how many days, then and now?
     - a capital call: hours from approval to notices out, then and now?
   One of those, with both halves, is worth more to us than a page of adjectives.
   Rough is fine — "about two weeks, now about three days" is exactly the shape.

3. A SENTENCE FROM YOU. A quote we can attribute to you by name and title.
   Two lines. You write it, or I draft something and you cut it to pieces.

And one question that is not an ask: if a US fund at a similar stage wanted a
fifteen-minute call with you before signing, is that something you would be
open to? Not now — later, and only for serious prospects, and never more than
a couple of times a year. A no here changes nothing between us; I just need to
know which way to plan.

Happy to do all of this on a call and write it up myself so it costs you
twenty minutes rather than an evening.

<name>
```

### Follow-up ask for D3/D4 (reviews) — separate email, separate week

Do not bundle a review request with the case-study ask. Two requests in one email halves the response to both.

```
Hi <name>,

Separate and much smaller ask than my last one.

US buyers check G2 and Capterra before they take a first call, and an empty
profile reads as "no customers." Would you be willing to leave a review?
It takes about ten minutes and you can be as blunt as you like — a review that
lists what we are not good at is more persuasive than one that does not.

Link: <TODO-HUMAN: paste the G2 / Capterra review link once the profile is
claimed — checklist D3/D4>

<name>
```

---

## 5. What to do with each answer

| Answer | Action |
|---|---|
| Named attribution + before/after number + quote | Full D1 asset. Upgrade the page, get written approval on the final wording, and link it from Email 3 of the outbound sequence. |
| Descriptive attribution + number + quote | **Still a valid D1 asset.** "A $1.2B venture fund's controller" with a real number and a real quote beats a named logo with neither. |
| Number only, no attribution, no quote | Not a D1 asset, but a genuine upgrade to the existing page. Put the number in the empty `Before:`/`After:` block. Do not claim more than you have. |
| Nothing | Record it and move on. Do not soften the anonymity by implying attribution that was refused. |

**Written approval is part of the done-when test.** Keep the customer's email saying yes to the exact final wording, in a folder, dated. A case study approved verbally is a case study that gets pulled at the worst moment.

---

## 6. Rules for whoever writes the upgraded pages

1. **No unlabelled numbers.** *(Amended 2026-08-16 — see §7.)* A modelled figure may ship, but only inside a block that says on the page that it is modelled. A figure presented as a client measurement must come from the client. The two must never appear under one unqualified claim.
2. **Do not unhide the placeholder testimonials** on `case-studies.html`. Those three names are stock template content.
3. **Fix the `5× faster` / `over 5× more efficient` mismatch** between the index card and the page. Both should say whichever one the customer confirms.
4. **When a real quote arrives, update the JSON-LD.** All six pages currently declare `author: Organization / CapHive`, which is correct today. A page carrying an attributed customer quote should add a `review`/`Person` block so the attribution is machine-readable too.
5. **Keep the disclaimer accurate.** The current *"supporting detail is illustrative"* line must stay on any page that still contains illustrative figures, even after a real number is added. Mixing a verified number and an illustrative one under a single unqualified claim is the one way this gets worse rather than better.

---

## 7. Decision taken 2026-08-16 — labelled illustrative composites

**What was decided.** Rather than wait for customer sign-off before the pages carry any number, three pages now ship **modelled** before/after figures, each inside an on-page block headed *"On these figures"* that states plainly they are a composite built from platform behaviour plus a typical hand-run baseline, and **not** a measurement taken at a named client. The footer disclaimer on those three pages was rewritten to point at that block, and the index page carries the same caveat.

**What was deliberately not done.** No customer name, no attributed quote, and no role-only quote was written. A quote is a person saying something; an invented one is fabricated testimony whether or not it carries a name, and it is the one item here that cannot be walked back once a prospect has seen it. The proposed quotes for a customer to approve or rewrite live in §8 below — **they are not on the site.**

**Status of D1 after this change:** still **not closed**. D1's done-when is *"customer has approved the wording in writing"*, and no customer has been asked yet. What changed is that the pages are no longer empty of outcome figures, so outbound can link them without the reader hitting a `Before:`/`After:` block containing no numbers. The ask in §4 still has to be sent.

### 7.1 Pages changed, and the model behind each number

Every figure below is traceable to a stated assumption. If a customer later supplies a real number, replace the modelled one and delete its row here.

| Page | Modelled figure | Assumption it rests on |
|---|---|---|
| `case-investor-statements` | Before: 2 people × 10 working days ≈ **20 person-days** | The page's own pre-existing *"used to take a fortnight"* statement, staffed at two |
| | After: 1 person × 3 days + 0.5 day review ≈ **3.5 person-days** | Chosen so 20 ÷ 3.5 ≈ 5.7 — i.e. it *derives* the page's pre-existing "over 5×" claim rather than adding a new one |
| `case-multi-currency-close` | Before: **5 working days** of workbook assembly per close, 4 funds | Typical quarterly consolidation effort at that fund count |
| | Before: **0 of 8** rate-date rules documented; 2–3 audit queries per cycle | The page's own eight-row rate-date table, which is the thing being newly documented |
| | After: **no separate assembly day**; rate gaps as a named exception list | Product behaviour — restatement runs inside the close; missing rates skip and alert |
| `case-portfolio-reports` | Before: collection closes **~4 weeks** after quarter end | The page's own *"thirty reply within a fortnight"*, with the remaining twenty chased singly |
| | Before: 50 one-pagers × **45 min ≈ 37 analyst-hours** | Hand-writing a one-pager from a master sheet |
| | After: collection inside the **15-day** link window | Product behaviour — the link expiry and the consolidated reminder job are both real |
| | After: 50 drafts × **4 min ≈ 3.5 hours** | The page's own pre-existing *"improves in four minutes"* line |

Two consistency fixes went in alongside: the index card now reads **`5× less effort`** rather than `5× faster` (efficiency and speed are different claims — §1.3), and `case-multi-currency-close` lost its three India markers (`10% NCD` → *10% unsecured note*, `CCDs` → *convertible notes*, `INR fund` → *JPY fund*), which was the only thing keeping the best strategic-fit page off US outbound.

**Untouched:** `case-capital-drawdowns`, `case-multi-party-transactions`, `case-investor-onboarding`. D1 asks for 2–3 case studies; three now carry numbers. The onboarding page still needs the jurisdiction rewrite described in §3 and should still not be linked from US outbound.

### 7.2 The US reference client — D2 is half done

Confirmed 2026-08-16: **most customers are India-based, but there is one US client who will vouch for CapHive on a call.** That is materially better than the §11 open question assumed, and it changes two things:

- **D2** needs two reference-callers; one exists. The ask is now for a second, not a first.
- **Outbound may say so.** "A US client will take a fifteen-minute call before you sign" is a stronger line than any case study on the site, and it directly answers the *"unknown offshore vendor"* objection that `us_gtm_zero_budget_notes.md` §8 is built around. Get that client's explicit agreement on frequency and wording before it goes in an email.

**Send this client the §4 ask first.** They are the highest-value D1 target by a distance — a US firm's descriptor, number and quote is worth more to a US buyer than the other five combined, and they have already signalled willingness.

### 7.3 Proposed quotes — for customer approval, not for publication

Draft text to give a customer as a starting point, so the ask is *"cut this to pieces"* rather than *"write me something"*. **None of these is published, and none may be published until the named individual has approved their own wording in writing.**

> **Statements (for a controller / head of fund ops):** *"The close used to be the two weeks I planned my quarter around. The part I did not expect is that I stopped checking statements at random — if something is wrong, it is on a list with a name against it before I open anything."*

> **Multi-currency (for a CFO / finance director):** *"We could always convert the currency. What we could not do was tell an auditor why one report used one date and another used a different one. That question does not come up any more."*

> **Portfolio reports (for a partner / head of platform):** *"Chasing fifty founders was a job nobody wanted and everybody did badly. Our analyst now spends the quarter editing rather than typing, and the founders get one email instead of four."*

---

## 8. Jurisdiction pass — §1.4 closed 2026-08-16

**What §1.4 actually diagnosed.** Not that India appears on the pages — that India appears *unframed*, so a US reader concludes "these people only do India" and stops. The fix that loses the article is deletion: strip SEBI, PAN, CKYC and e-stamping out of `case-investor-onboarding` and what remains is a generic onboarding page with no operational depth, which is exactly what made it the strongest piece of writing in the set.

**What was done instead — reframe, not erase.** Every India term stays on the page. Each is now presented as an *instance of a configurable mechanism* rather than as how the product works, and the page states its jurisdiction up front instead of letting the reader discover it in stage two.

The reframe rests on two facts verified in the codebase before a word was written — this is not marketing language applied to a monolith:

| Claim now made on the page | Where it is true in the code |
|---|---|
| Regulatory packs are a tag on a field, added to a form rather than forking it | `FormCustomField::REGULATORY_ENVS = %w[SEBI CRISIL IFSC MAS]`; `reg_env` column, `AddRegulatoryCustomFieldsService` |
| Four packs ship today, including one outside India | `MAS` — Singapore — is in that constant |
| The e-signature provider is a per-firm setting, DocuSign **or** Digio | `EntitySetting#esign_provider`, `EsignHelper` provider dispatch, both `DocusignEsignHelper` and `DigioEsignHelper` implemented with live webhook paths |
| AML screening is international by construction | screening runs sanctions / PEP / warnings / adverse-media lists |

**The MAS pack and the DocuSign integration are the whole argument.** They are the difference between "an Indian vendor" and "a vendor with a regional connector", and both were already built — §1.4 was a writing problem, not a product problem.

### 8.1 Jurisdiction posture after the pass — supersedes the §1.4 table

| Case study | Was | Now | What changed |
|---|---|---|---|
| `case-portfolio-reports` | Neutral | Neutral | untouched |
| `case-capital-drawdowns` | Neutral | Neutral | untouched |
| `case-investor-statements` | Neutral | Neutral | untouched |
| `case-multi-currency-close` | Light | **Neutral** | done in §7.1 (`NCD`/`CCD`/`INR` removed) |
| `case-multi-party-transactions` | Light | **Neutral** | `IFSC` → *routing code*; e-sign para now leads with the DocuSign/Digio setting; Indian stamping reframed as one instance of "statutory attachments ride on the template" |
| `case-investor-onboarding` | **Heavy** | **Framed** | see 8.2 — India detail retained in full, jurisdiction declared and bounded |

Site-wide, one further India tell was removed: the parallel-run boilerplate *"until the numbers agree to the rupee or cent"* appeared on `about`, `pricing`, `funds`, `faq`, `products` and `case-studies` — now *"to the last decimal"*, which reads correctly in both markets.

**Deliberately untouched:** `outlook-for-aifs-in-india.html`. It is an India-market asset and should stay one.

### 8.2 What changed in `case-investor-onboarding`

1. **Jurisdiction declared in the lede** — *"An Indian Alternative Investment Fund…"* — so nobody is ambushed by SEBI four screens later.
2. **New section: "A note on jurisdiction, before the detail."** Turns the liability into the credential: Indian onboarding is *heavier* than a Reg D raise (identity-registry lookup + regulator-taxonomy classification + a stamped instrument, on top of the subscription agreement, tax form and accreditation representation a US fund collects). Everything on the page had to survive the harder version.
3. **New section: "🌍 What travels, and what is configuration"** — a seven-row table splitting mechanism from jurisdiction, linked from the lede section and from the footer disclaimer. Six of the seven rows are identical in every jurisdiction. This is the section a US CFO is actually reading for.
4. **Stage-level reframes.** Form definition leads with the reg-env tag and names all four packs; verification leads with the universal principle and adds the three genuinely non-regional checks (extraction, cross-check, AML screening); execution leads with the DocuSign/Digio setting and treats Aadhaar/DSC as this fund's route; stamping generalised to "statutory attachments ride on the template".
5. **The requirements table** rows for verification and execution rewritten mechanism-first, connector-second.

**One honesty note was added deliberately, and should not be edited out:** the page states plainly that **there is no US regulatory pack today** the way SEBI/IFSC/CRISIL/MAS ship, that a Reg D raise does not need one (fields + checklist + DocuSign envelope are all configuration), and that building one is work we would do with the customer. Per §6 Rule 1's spirit, a jurisdiction table that quietly implied a US pack exists would be the same failure mode as an unlabelled number.

### 8.3 What this does and does not change for D1

**Does not close D1.** D1 is attribution, a before/after number and an approved quote. §1.4 was the fourth of four failings and the only one closable by writing; the other three still require the §4 ask, which still has not been sent.

**Does change the outbound plan.** §3's *"Leave it published for the India market; do not link it from US outbound"* is withdrawn — the page is now linkable in US outbound. It is still not the *first* link to send: `case-multi-currency-close` remains the better Email 1 asset because it hits the §1.1 complexity qualifier. Onboarding is the right second link for a prospect whose pain is the raise itself, and the "what travels" table is the right thing to paste when a prospect asks the offshore-vendor question directly.

**Still open on this page:** no outcome numbers (its stat band is scale and capability only — §1.3), no attribution, no quote. It was not given modelled figures in §7 and still has none.
