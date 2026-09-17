# Outbound Tracker — How to Use It

**File:** `outbound_tracker.csv` (currently headers only — seed it with the script below)
**Why it exists:** manual sending is fine at ~25 accounts/week; manual state-keeping is not. Emails 2–4 produce most of the replies, and by week four there are ~100 accounts in flight across four touches each. Without this sheet the sequence degrades into one-and-done emails, which is the version that does not work. **It must exist before the first send.**

---

## Seeding it

Run the ADV filter first (`../gtm_prerequisites_work/scripts/adv_filter.py`), which writes a CSV of the advisers matching §1.1. Then:

```bash
python3 scripts/make_tracker.py --input adv_matches.csv --output outbound_tracker.csv
```

Account columns arrive pre-filled; contact and sequence columns are blank and ready for the research pass. If a column cannot be resolved from that ADV vintage the script says so on stderr and leaves it blank rather than guessing — a silently empty column would otherwise read as "ADV does not carry this."

To regenerate an empty template: `python3 scripts/make_tracker.py --template-only`.

Import into Google Sheets rather than working in the raw CSV — you want filters and sorting.

---

## The daily working view

**Sort by `next_touch_date`, filter to today or earlier.** That is the whole system. Everything due is at the top; if the list is empty, outbound is done for the day.

The single most common failure is leaving `next_touch_date` blank after sending an email. If it is blank the account disappears from the working view and never gets a follow-up. Set it every time you send, in the same action.

---

## Columns

| Group | Columns | Notes |
|---|---|---|
| **Account** | `crd_number`, `firm_name`, `city`, `state`, `raum_usd`, `private_fund_count`, `fund_types`, `website` | Pre-filled from ADV. `crd_number` is the stable join key back to the source data. `fund_types` with 2+ distinct values is the SPV/parallel-fund proxy — ADV has no direct field for it. |
| **Contact** | `contact_name`, `title`, `persona`, `email`, `email_verified`, `linkedin_url` | `persona` is CFO / COO / IR and selects which sequence in `sequences/` to use. |
| **Sequence** | `personalization_hook`, `email_1_sent` … `email_4_sent`, `next_touch_date`, `status` | Dates in `YYYY-MM-DD`. `personalization_hook` records the specific fact the opening line was built on — useful later when you are trying to work out which hooks actually produce replies. |
| **Outcome** | `reply_type`, `meeting_booked_date`, `disqualified_reason`, `opted_out`, `notes` | `disqualified_reason` comes from `qualification_screen.md`. |

**Status values:** `not_started` → `researching` → `sending` → `replied` → `meeting_booked`, plus the two exits `disqualified` and `opted_out`.

---

## Two rules that are not optional

1. **`email_verified` must read `verified` before anything is sent.** Hard bounces are the largest reputation risk to `caphive.com`, which also carries all transactional mail — capital call notices and investor statements included. Never send to `unchecked` or `invalid`.
2. **`opted_out = yes` is permanent and immediate.** Set it the moment someone asks, and never send to that row again regardless of what `next_touch_date` says. This is a legal requirement under CAN-SPAM, not a courtesy, and at this volume it is honoured by hand — which means it depends entirely on discipline.

---

## Weekly reporting

The GTM plan's §5 kill criteria need four numbers, all derivable from this sheet:

- **Accounts sequenced** — rows where `email_1_sent` is set
- **Reply rate** — rows where `reply_type` is not `none` ÷ accounts sequenced
- **Meetings booked** — rows with a `meeting_booked_date`
- **Opt-out rate** — a leading indicator of a targeting problem; if it climbs above ~2%, the list is wrong before the message is

Note the checkpoint is **300 accounts sequenced**, not 300 emails — with a four-email sequence those differ by roughly 4×. And per §5, that checkpoint is a stop-signal, not a basis for A/B testing.
