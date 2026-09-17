# Message Testing Plan

**The criterion under test** ([`us_gtm_zero_budget_notes.md`](../us_gtm_zero_budget_notes.md) §5):

> **Cold email — reply rate < 1% after 300 sends → the list or the message is wrong. Fix before adding volume, do not scale through it. Check at Week 12.**

This document says how to run that test so the answer is readable, and — more importantly — how to tell **which** of "the list" and "the message" was wrong, because the criterion as written does not distinguish them and the two have opposite fixes.

---

## 1. Define "300 sends" before the first email goes out

§5 says "300 sends". §3.2 says "150–200 highly personalized **emails**/week". These are not the same unit, and with a 4-email sequence they differ by roughly **4×**.

| Reading | 300 sends means | Accounts contacted |
|---|---|---|
| **Per email** | 300 individual messages | ~75–100 accounts |
| **Per account** | 300 accounts entering the sequence | ~1,050 individual messages |

**Use the per-account reading.** Three reasons: reply rate per account is the number that predicts meetings; a reply to email 3 is a success for the whole sequence, not for email 3; and 75–100 accounts is far too few to conclude anything about a list, which is half of what the criterion is supposed to diagnose.

> **Definition, to be adopted explicitly:** *reply rate = distinct accounts that produced a human reply to any email in the sequence ÷ accounts that entered the sequence and received at least email 1 without a hard bounce.*

Excluded from the numerator: out-of-office auto-replies, bounce notifications, unsubscribe clicks. **Included:** "not interested", "wrong person", and anything hostile. A negative reply is a signal that the message landed and was read, which is exactly what the criterion is measuring.

`TODO-VERIFY:` this reading roughly quadruples the volume implied by §5, which pushes the 300-account checkpoint from Week 12 to around Week 13 at 50 accounts/week starting in Phase 1 (Week 5). Confirm the founders intend the per-account reading before the checkpoint is scheduled, because it changes what "Week 12" means.

---

## 2. The uncomfortable arithmetic — read this before designing any split test

At a 1% reply rate, 300 accounts produce **three replies**.

**What a single arm of 300 can actually tell you.** Observing 3 replies out of 300 gives a 95% confidence interval of roughly **0.34% to 2.90%** (Wilson). The point estimate is 1%; the truth could be a third of that or three times it. The 300-send checkpoint therefore cannot distinguish "1%" from "2%" at all. What it *can* distinguish is **alive from dead** — 0 replies versus 6 replies is a real difference. That is precisely what §5 is for, and it is a smoke test, not a measurement.

**What it takes to compare two messages.** Sample size per arm, two-proportion test, α = 0.05, power = 0.80:

| Comparison | Accounts needed **per arm** | At 150 accounts/week |
|---|---|---|
| 1% vs 2% (a doubling) | ~2,320 | ~31 weeks per arm |
| 1% vs 3% (a tripling) | ~770 | ~10 weeks per arm |
| 1% vs 5% (a 5× difference) | ~285 | ~4 weeks per arm |

> **Conclusion, and it governs the rest of this document: do not A/B test at the 300-send checkpoint.** Splitting 300 accounts into two arms of 150 yields perhaps two replies versus one. That difference is indistinguishable from a coin flip, and acting on it is worse than not testing — it manufactures a false conclusion that then gets scaled.
>
> The only differences this program can ever detect are **large** ones. Design the tests to look for large differences, and accept that body copy is not where large differences live.

---

## 3. Test design — sequential blocks, not concurrent splits

**One message, one list segment, 300 accounts, then read.** Then change exactly one thing and run the next block of 300. Slower than a split test, but it is the only design that produces a readable result at this volume, and it has a second advantage: with a single arm running at any time, deliverability problems are attributable rather than confounded.

### Block plan

| Block | Accounts | What changes | Question answered |
|---|---|---|---|
| **0 — Deliverability smoke test** | 30 | Nothing. Sent after domain warm-up | Do these land in an inbox at all? |
| **1 — Baseline** | 300 | Nothing. Single persona, single segment, single hook family | Is the channel alive? *This is the §5 checkpoint* |
| **2 — First iteration** | 300 | **One** variable, chosen by the §6 diagnosis | Did the diagnosed problem move the number? |
| **3 — Second iteration** | 300 | One variable | Same |
| **Stop decision** | — | After block 3 (900 accounts, ~3 fix cycles) | See §7 |

### Block 0 is not optional

Thirty accounts, sent slowly, before the real test starts. Check: hard bounce rate, whether SPF/DKIM/DMARC pass on receipt (prerequisite C3), and — using seed mailboxes on Gmail, Outlook 365 and one corporate domain — whether the message reaches the inbox or Promotions/Junk.

**A deliverability failure looks exactly like a message failure in the reply-rate number, and it is far more common.** Spending 300 accounts to discover the domain was in a spam folder is the single most expensive mistake available here, because those 300 accounts are burned and the list cannot be re-bought.

---

## 4. Held constant — the whole time

Changing any of these mid-block invalidates the block. Log the change if it happens, and restart the block.

| Held constant | Why |
|---|---|
| **Sender identity** (name, title, mailbox) | The largest single driver of cold-email reply rate. Varying it varies everything |
| **Sending domain and mailbox rotation pattern** | Reputation is per-domain and moves slowly |
| **Send window** — 8–11am recipient local time, Tue–Thu | Day and hour effects are real and would swamp a copy effect |
| **Sequence length and spacing** — 4 emails, +4/+6/+8 business days | |
| **Signature block and CAN-SPAM footer** | Footer mechanics owned by prerequisite C6 |
| **Link policy** — one link maximum, from the verified list | |
| **Plain text, no attachments, no tracking pixel** | An image pixel is a spam signal and, since Apple Mail Privacy Protection and corporate link-scanners, open rates are not trustworthy data anyway |
| **The QA checklist** (`personalization_framework.md` §7) | An unenforced quality floor turns any test into a test of that week's care level |
| **Daily send volume per mailbox** (~30) | Volume changes move deliverability, which moves reply rate |

---

## 5. What to vary — in this order, one per block

Ordered by expected effect size. **The first two are worth testing at this sample size. The last two are not.**

### Tier 1 — large expected effects, test these

**1. List segment (biggest lever by a distance).** §5's own wording puts "the list" before "the message". Segment definitions worth testing against each other in sequential blocks:

- Self-administered firms (Q26(a) = No on any fund) vs. firms with a third-party administrator
- Firms with a confirmed cross-border signal (Q16 > 25%, or a non-US Q2 jurisdiction) vs. domestic-only
- 3–4 vehicles vs. 5+ vehicles
- Active Form D in the last 6 months vs. not

If a wrong list is the problem, this is where it shows, and the effects can genuinely be 3–5×.

**2. Persona routing.** Same firms, but entering via CFO vs. COO vs. IR. `us_gtm.md` §2.2 names the COO the primary champion; that is a hypothesis, not a finding, and it is cheap to test. Route by title at the account level and compare blocks.

### Tier 2 — moderate effects, test only after Tier 1 is settled

**3. The hook family.** `personalization_framework.md` §3 gives ten Tier 1 hooks. Group them into families — structural (self-administered, master-feeder, vehicle count) versus relational (administrator name, funds of funds, placement agent) — and vary the *family*, never an individual hook. Individual hooks fire on too few accounts to accumulate a readable sample.

**4. The ask.** Genuinely different asks, not rephrasings:
- a diagnostic question ("is that check written down, or is it someone's habit?")
- a meeting request ("worth 20 minutes?")
- the configure-first offer (currently email 3 of the COO sequence — test it as email 1)

The configure-first offer as an opener is the most interesting untested idea in these sequences and could plausibly produce a large effect in either direction.

### Tier 3 — do not test at this volume

**5. Subject lines.** The variants in each sequence file exist so that one can be *chosen and held constant*, not so they can be split-tested. Detecting a subject-line effect needs open-rate data we have deliberately given up, and reply-rate-based subject testing needs thousands of sends per arm.

**6. Body copy rewrites.** A better sentence is worth less than a better list by an order of magnitude, and it is undetectable at 300. Rewrite copy when it is wrong, not as an experiment.

---

## 6. Reading the result — which was wrong, the list or the message?

At the block 1 checkpoint, do not look at reply rate alone. Read this table top to bottom and stop at the first row that matches.

| Diagnostic | Threshold | Reading | Fix |
|---|---|---|---|
| **Hard bounce rate** | > 3% | Contact data quality, not messaging | Fix email verification before anything else. Bounces also damage the domain, so this is urgent, not just informative |
| **Spam complaint rate** | > 0.1% | Deliverability and/or list relevance | Pause sending. Re-check warm-up, volume ramp and segment relevance |
| **Seed inbox placement** | Any seed in Junk/Promotions | Deliverability | Nothing about copy matters until this is fixed. Re-run block 0 |
| **Zero replies of any kind, including negatives** | 0/300 | Almost always deliverability or a dead list — a *read* message produces some "no" | Verify placement first; then question whether the contacts are real people in those roles |
| **Negatives but no positives** | e.g. 4 replies, all "not interested" | **Message/offer problem.** They read it and it did not land | Change the ask (Tier 2, item 4), then the hook family |
| **Positives, but from the wrong titles** | Replies from analysts, associates, admins | **Persona routing problem** | Fix title targeting (Tier 1, item 2) |
| **Positives that disqualify on the call** | Meetings booked, then failed the §1.1 screen | **List definition problem** — the message works | Tighten the filter. Read the `qualification_screen.md` §8 write-ups for the pattern |
| **Positives that qualify** | ≥ 3 qualified meetings | **The channel works.** Scale it | Proceed to Phase 2 volume |

**The decisive signal is the ratio of negative to zero.** Silence means unread or undelivered. "No thanks" means read and rejected. Those are opposite problems, and reply rate alone conflates them — which is the main weakness of §5 as written.

**Second decisive signal: what the qualified meetings said.** Per `qualification_screen.md` §8, when several calls disagree with the ADV row in the same direction, that is a filter bug. Fixing the filter is a list fix and is usually worth more than any copy change.

---

## 7. "Fix" versus "stop"

§5 says "fix before adding volume, do not scale through it" but does not define the exit. Without one, a failing channel runs forever on founder time — the exact failure mode §5 exists to prevent.

### A fix looks like

- One diagnosed problem from the §6 table
- One variable changed, from the Tier 1 or Tier 2 lists
- A fresh block of 300 accounts, **drawn from a part of the list that has never been contacted** — re-contacting burned accounts contaminates the result and annoys the market
- Everything in §4 still constant
- A written hypothesis recorded *before* the block starts, in the form: *"Reply rate was 0.7%, all four replies negative. Hypothesis: the ask is too large for a first email. Changing the email 1 ask from a meeting request to a diagnostic question. Expect ≥2%."* Recording it beforehand is what stops a disappointing result being retro-fitted into a success.

### A stop looks like

**Trigger: three fix cycles — blocks 1, 2 and 3, 900 accounts total — with reply rate still under 1% and no qualified meeting.**

At that point the honest reading is that cold outbound is not going to be one of the five, and §6's funnel — *2 from warm paths, 2 from cold outbound, 1 from inbound* — needs re-planning rather than more sends. A stop does **not** mean "send nothing":

- Drop to maintenance volume: ~25 accounts/week, top-tier accounts only, personalized properly
- Reallocate the recovered hours to §3.1 warm paths, which the plan already ranks as the cheapest channel and calls "chronically under-used"
- Escalate to a plan-level decision: if cold cannot carry 2 of the 5, either warm carries 4 and the partner motion needs its own targets, or the 8–12 month timeline moves
- Re-open outbound when a real asset changes — an approved case study with a named customer (prerequisite D1), a US reference (D2), or a live G2 profile (D3). Those are exactly the things §4 says make cold email work, and they are the most likely reason a well-executed sequence underperforms today

### Two things that are neither a fix nor a stop, and must not happen

1. **Scaling through it.** Going from 50 to 150 accounts/week on a message that is not replying multiplies the damage rather than the data. §5 is explicit.
2. **Changing three things at once.** It converts an unreadable result into an uninterpretable one, and it is the most common instinctive response to a bad number.

---

## 8. Instrumentation

Per account, in the sequencer. Most of these already exist in `personalization_framework.md` §9.

`account_id` · `block_id` · `segment_id` · `persona` · `hook_id` · `hook_family` · `ask_variant` · `subject_variant` · `sender` · `date_email_1` … `date_email_4` · `hard_bounce` (bool) · `soft_bounce_count` · `unsubscribed` (bool) · `spam_complaint` (bool) · `link_clicked` (bool, from the UTM convention in prerequisite B5) · `replied` (bool) · `reply_sentiment` (positive / neutral / negative / redirect) · `reply_to_email_n` · `meeting_booked` (bool) · `qualified` (from `qualification_screen.md` §8) · `disqualify_reason`

**`reply_sentiment` and `hook_id` are the two fields that make the §6 diagnosis possible.** Without sentiment, silence and rejection are indistinguishable. Without `hook_id`, a low rate cannot be attributed to the hook rather than the message. If the sequencer will not carry custom fields, keep them in a spreadsheet — they matter more than the tool does.

---

## 9. Weekly readout — five lines

§5 already asks for weekly tracking of emails sent, reply rate, meetings booked, pilots proposed, and warm intros requested vs. received. Add three diagnostics and cap the readout at five lines so it actually gets written:

1. Accounts entered this week / cumulative in the current block
2. Hard bounce % and spam complaint % *(guardrails — act immediately, do not wait for the block to close)*
3. Replies, split positive / neutral / negative / redirect
4. Meetings booked, and how many passed the §1.1 screen
5. Anything that changed in the §4 held-constant list *(should be blank; if it is not, the block is invalid)*

**Do not compute a reply rate before the block closes.** Reading 1 reply out of 40 as "2.5%" mid-block and reacting to it is how a good message gets rewritten on noise. Read the block at 300 and not before — that is the entire discipline this document is asking for.
