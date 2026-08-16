# D1 — Case Study Gap Analysis and Customer Ask

**Checklist row:** D1 in [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md)
**Done when:** 2–3 written case studies with hard numbers, wording approved by the customer in writing.
**Status:** **BLOCKED-NEEDS-HUMAN.** Six case studies already exist and are good content marketing. **None of them satisfies D1**, and the gap cannot be closed by writing — it can only be closed by asking customers for three things. This document is the gap analysis and the ask.

**Nothing here invents a metric, a customer name, or a quote.** Every number quoted below is quoted from the existing pages as written.

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

1. **No invented numbers.** If the customer will not give one, the page ships without one.
2. **Do not unhide the placeholder testimonials** on `case-studies.html`. Those three names are stock template content.
3. **Fix the `5× faster` / `over 5× more efficient` mismatch** between the index card and the page. Both should say whichever one the customer confirms.
4. **When a real quote arrives, update the JSON-LD.** All six pages currently declare `author: Organization / CapHive`, which is correct today. A page carrying an attributed customer quote should add a `review`/`Person` block so the attribution is machine-readable too.
5. **Keep the disclaimer accurate.** The current *"supporting detail is illustrative"* line must stay on any page that still contains illustrative figures, even after a real number is added. Mixing a verified number and an illustrative one under a single unqualified claim is the one way this gets worse rather than better.
