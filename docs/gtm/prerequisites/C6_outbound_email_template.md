# C6 — CAN-SPAM Compliant Outbound Sequence

**Checklist row:** C6 in [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md)
**Done when:** the template carries a real postal address, a working unsubscribe, and honest subject lines — and an unsubscribe click actually suppresses the address in the sequencer.
**Status:** DRAFTED. The template below is complete and compliant. The **"done when" test is not satisfiable by drafting** — it requires the sequencer from C5 to exist and a live suppression test. See §6.

> **Not legal advice.** This reflects the plain requirements of 15 U.S.C. §7704 and the FTC's CAN-SPAM compliance guide. Have counsel confirm before the first send, particularly the postal address question in §5.

---

## 1. What CAN-SPAM actually requires

Five obligations. All five are met by the template in §3; the fourth and fifth are tooling, not copy.

| # | Requirement | How the template meets it |
|---|---|---|
| 1 | **No false or misleading header information.** From, To, Reply-To and routing must identify the sender accurately. | Send from a real named mailbox on the secondary domain (C2). Never a display name that implies a different company, and never a spoofed Reply-To. |
| 2 | **No deceptive subject lines.** The subject must reflect the message's content. | Every subject in §3 describes what the email is. Banned outright: `Re:` / `Fwd:` on a first touch, `Following up on our call` when there was no call, `Quick question` attached to a pitch, anything implying an existing relationship. |
| 3 | **Identify the message as an advertisement.** May be done in any conspicuous way. | Handled by the signature block: the sender is plainly identified as CapHive with a company address and a commercial purpose stated in the body. |
| 4 | **Include a valid physical postal address.** | In the footer of every email. See §5 — this is the one open question. |
| 5 | **Clear opt-out, honoured within 10 business days, free, and no more than one step.** | One-click unsubscribe link in every footer. Must be a real link, not "reply STOP" only. Suppression must be verified — §6. |

Two more that are not CAN-SPAM but matter:

- **Opt-out must not require a login or any information beyond the email address.** A form asking why they are leaving before it will unsubscribe them is non-compliant.
- **You remain liable for a third party sending on your behalf.** If the sequencer is misconfigured, that is still on CapHive.

---

## 2. Merge fields — and where each one comes from

Every field below is populated from the Form ADV extract produced by
[`scripts/adv_filter.py`](scripts/adv_filter.py) (see [`F_form_adv_findings.md`](F_form_adv_findings.md)), except the two marked **manual**, which are the 10–15 min/account of research the GTM plan budgets for.

| Field | Source | Notes |
|---|---|---|
| `{{first_name}}` | **manual** | Person research. Never send with this blank or defaulted to "there". |
| `{{title}}` | **manual** | CFO / COO / Controller / Head of Finance. |
| `{{firm}}` | ADV `Primary Business Name` | Use the trading name, not the legal entity with "LLC" appended. |
| `{{fund_count}}` | ADV `Count of Private Funds - 7B(1)` | The single most useful personalisation token available for free. |
| `{{strategy}}` | ADV per-fund-type counts | "private equity", "venture", "real estate", "multi-strategy". |
| `{{city}}` | ADV main-office city | Light touch only; do not lead with it, it reads as mail-merge. |

**Do not merge RAUM into the body.** Telling a CFO you know their AUM reads as surveillance rather than research, even though the number is public. Use it to *segment* the list, not to write the sentence.

---

## 3. The sequence — four emails

Personalisation carries these, not volume. At 150–200/week with $60K+ ACV, the 10–15 minutes per account is trivially justified.

### Email 1 — Day 0

**Subject:** `{{fund_count}} vehicles, one allocation spreadsheet?`
*Alternate:* `question about {{firm}}'s quarter close`

```
Hi {{first_name}},

Your ADV shows {{firm}} running {{fund_count}} private fund vehicles. In my
experience that is the point where allocations stop being a spreadsheet problem
and start being a reconciliation problem — particularly across parallel vehicles
and SPVs, where the same LP shows up under three different commitment bases.

I build CapHive, a fund operations platform for exactly that structure. I am not
asking for a meeting in this email. I am asking whether that is a real problem at
{{firm}} or one I have invented.

If it is real, this is the piece I would read first — it is the edge cases, not
the pitch:
https://caphive.com/side-letter-obligations.html?utm_source=coldemail&utm_medium=email&utm_campaign=2026q3-outbound-midmarket-gp&utm_content=email1

If it is not, say so and I will leave you alone.

<SIGNATURE — see §4>
```

### Email 2 — Day 4

**Subject:** `re: allocations across {{fund_count}} vehicles`
*(Legitimate `re:` — this genuinely follows Email 1 in the same thread. Never use it on a first touch.)*

```
Hi {{first_name}},

Following my note on allocation across {{firm}}'s vehicles — one specific thing,
in case it is the thing.

The quarter close most funds describe to me breaks in the same place: the
management-fee calculation is right, the allocation is right, and the two disagree
because a mid-quarter close changed the commitment base and only one of them was
rebuilt. Then someone reconciles by hand for three days.

If that is recognisable, I would be glad to show you how CapHive handles it —
against your structures, not a demo dataset.

<SIGNATURE>
```

### Email 3 — Day 11

**Subject:** `how {{strategy}} funds are handling multi-currency close`

```
Hi {{first_name}},

Last one on this thread with something new in it.

<TODO-HUMAN: link the case study here once D1 is complete — a NAMED or credibly
described customer with a real before/after number. Do NOT ship this email with
the current anonymous case studies as the proof point; an unattributed claim in a
cold email is worse than no claim, because it invites the exact scepticism the
email exists to overcome. Until D1 lands, cut this email to three and go straight
to the breakup.>

<SIGNATURE>
```

### Email 4 — Day 21 (breakup)

**Subject:** `closing the loop`

```
{{first_name}},

I have not heard back, which I read as "not now" rather than "never" — so this is
my last email.

If fund operations at {{firm}} become a priority later, I am easy to find. And if
the honest answer is that your current setup works, I would genuinely like to know
what you are using; I learn more from that than from the ones who say yes.

<SIGNATURE>
```

---

## 4. Signature and footer block — required on **every** email in the sequence

```
--
<Full name>
<Title>, CapHive
<booking link — checklist A3/A4, the same URL used on the site>
https://caphive.com

CapHive
167 Madison Avenue, Suite 205 #4854
New York City, NY 10016
United States

You received this because your firm appears in the SEC's public Form ADV
register and I thought CapHive was relevant to it. If it is not, unsubscribe
here and I will not contact you again:
{{unsubscribe_link}}
```

Notes on this block, each one load-bearing:

- **The postal address is a CAN-SPAM requirement, not decoration.** It must appear in every commercial email, including the breakup.
- **`{{unsubscribe_link}}` must be the sequencer's own token**, so the click writes to the suppression list. A `mailto:` unsubscribe alone is not sufficient and is easy to miss.
- **Stating why they were contacted is not required** but it is the cheapest trust move in the whole email — it answers "how did you get my address" before it is asked, and the answer happens to be "a public federal register".
- **Do not add tracking pixels** on a list this small and this valuable. Open tracking inflates deliverability risk for negligible signal at 150–200 sends/week, and Apple Mail Privacy Protection has made open rates meaningless anyway. Track replies and clicks only.
- **Do not attach anything.** Attachments on cold email are a strong spam signal. Link instead.

---

## 5. TODO-VERIFY: the postal address

The address above is taken verbatim from the New York office block on
`website_src/pages/contact.html`. Two things need a human before the first send:

1. **`Suite 205 #4854` has the shape of a virtual-office / mail-forwarding suite.** CAN-SPAM permits a registered post-office box or a private mailbox registered with a Commercial Mail Receiving Agency, so this is very likely compliant — but confirm it is a real, current, CMRA-registered address that receives mail, not a lapsed listing. An address that bounces is worse than none: it is the first thing a sceptical recipient checks.
2. **Confirm which entity name goes above it.** Until the US entity exists (checklist G1), the sending entity is the Indian company. Whether the footer should read `CapHive`, the Indian legal entity name, or both is a question for counsel — it interacts with requirement 1 (no misleading identification), and it is the sort of detail a fund's GC notices.

---

## 6. Why C6 cannot be closed from here

The row's done-when test is **"an unsubscribe click actually suppresses the address in the sequencer."** That requires:

- C5 complete — a sequencer selected and paid for. **BLOCKED-NEEDS-HUMAN**, requires payment.
- C1/C2 complete — the secondary domain and mailboxes exist.

Then run this test, in this order, before any real send:

1. Load the template into the sequencer with the footer from §4 intact.
2. Add a personal address you control as a one-row test list. Send.
3. Click the unsubscribe link in the received message. Confirm it takes **one** click and asks for nothing.
4. Confirm the address now shows as suppressed/unsubscribed in the sequencer UI.
5. **Add the same address to a second, different sequence and attempt to send.** This is the step people skip, and it is the one that matters: many tools suppress per-sequence rather than per-account by default. If it sends, find the account-level suppression setting and turn it on.
6. Send a test to a Gmail address and check "Show original" for SPF, DKIM and DMARC all passing (this also closes C3).

Record the date this was run. Re-run it whenever the sequencer or the template changes.
