#!/usr/bin/env python3
"""
make_tracker.py -- Seed the outbound tracking sheet from the Form ADV extract.

WHY THIS EXISTS
---------------
Cold outreach in this plan is sent by hand, by the CEO, from his own mailbox
(see docs/gtm/us_gtm_zero_budget_notes.md section 3.2). Manual sending is
fine at ~25 accounts/week. Manual STATE-KEEPING is not: emails 2-4 produce most
of the replies, and by week four there are ~100 accounts in flight across four
touches. Without a sheet the sequence quietly degrades into one-and-done emails.

So the tracker has to exist before the first send, and it has to open pre-filled
with real accounts -- a blank template that someone has to design at 7am is a
template that never gets used.

INPUT
-----
The CSV written by ../prerequisites/scripts/adv_filter.py, which
contains the advisers matching the section 1.1 profile ($300M-$2B RAUM, 3+
private funds).

Column names drift between ADV vintages, so every field is resolved through a
list of candidate headers rather than a hardcoded name -- same approach the
filter script uses. Anything unresolved is left blank rather than guessed.

OUTPUT
------
outbound_tracker.csv -- one row per account, account columns pre-filled, contact
and sequence columns blank and ready for the research pass.

USAGE
-----
    python3 make_tracker.py --input adv_matches.csv --output outbound_tracker.csv
    python3 make_tracker.py --template-only        # headers only, no input needed
"""

import argparse
import csv
import sys

# --- Column layout of the tracker ------------------------------------------
# Grouped by lifecycle stage so the sheet reads left-to-right in the order the
# CEO actually works it: who they are, who to write to, what was sent, what
# came back.

ACCOUNT_COLS = [
    "crd_number",           # stable SEC identifier -- the join key back to ADV
    "firm_name",
    "city",
    "state",
    "raum_usd",             # regulatory AUM, Item 5.F.(2)(c)
    "private_fund_count",   # Schedule D Section 7.B.(1) -- the 3+ qualifier
    "fund_types",           # 2+ distinct types is the SPV/parallel proxy
    "website",
]

CONTACT_COLS = [
    "contact_name",
    "title",
    "persona",              # CFO | COO | IR  -- selects which sequence to use
    "email",
    "email_verified",       # verified | invalid | risky | unchecked
    "linkedin_url",
]

SEQUENCE_COLS = [
    "personalization_hook", # the specific fact the opening line is built on
    "email_1_sent",         # dates, ISO format YYYY-MM-DD
    "email_2_sent",
    "email_3_sent",
    "email_4_sent",
    "next_touch_date",      # THE column that makes the sheet work -- sort on it
    "status",               # see STATUS_VALUES below
]

OUTCOME_COLS = [
    "reply_type",           # positive | neutral | negative | none
    "meeting_booked_date",
    "disqualified_reason",  # from qualification_screen.md
    "opted_out",            # yes | no -- CAN-SPAM, must be honoured immediately
    "notes",
]

HEADER = ACCOUNT_COLS + CONTACT_COLS + SEQUENCE_COLS + OUTCOME_COLS

# Documented here rather than only in the companion markdown, so the meaning
# travels with the file that uses it.
STATUS_VALUES = [
    "not_started",    # in the list, nothing done
    "researching",    # finding the contact and verifying the address
    "sending",        # sequence in flight
    "replied",        # any reply -- see reply_type
    "meeting_booked",
    "disqualified",   # failed the qualification screen
    "opted_out",      # asked not to be contacted -- never send again
]

# --- Input column resolution ------------------------------------------------
# Each tracker field maps to a list of candidate ADV headers, tried in order,
# case-insensitively and ignoring surrounding whitespace. First hit wins.

SOURCE_CANDIDATES = {
    "crd_number": ["crd_number", "crd", "Organization CRD", "1E1"],
    "firm_name": ["firm_name", "Primary Business Name", "legal_name", "1A"],
    "city": ["city", "Main Office City", "1F1-City"],
    "state": ["state", "Main Office State", "1F1-State"],
    "raum_usd": ["raum_usd", "raum", "5F2c", "Total RAUM"],
    "private_fund_count": [
        "private_fund_count", "fund_count",
        "Count of Private Funds - 7B(1)", "7B1_count",
    ],
    "fund_types": ["fund_types", "fund_type", "private_fund_types"],
    "website": ["website", "Website Address", "1I1"],
}


def resolve_columns(fieldnames):
    """Map tracker field -> actual input header, or None when absent.

    Returns a dict and prints a one-line report per unresolved field, because a
    silently-empty column is worse than a loud gap: the CEO would otherwise
    assume the data simply was not in ADV.
    """
    normalized = {name.strip().lower(): name for name in (fieldnames or [])}
    resolved = {}
    for field, candidates in SOURCE_CANDIDATES.items():
        match = None
        for candidate in candidates:
            hit = normalized.get(candidate.strip().lower())
            if hit:
                match = hit
                break
        resolved[field] = match
        if match is None:
            print(f"  note: no source column for '{field}' -- left blank",
                  file=sys.stderr)
    return resolved


def build_rows(reader, resolved):
    """One tracker row per input row. Account columns filled, the rest blank."""
    for source_row in reader:
        row = {col: "" for col in HEADER}
        for field, source_col in resolved.items():
            if source_col:
                row[field] = (source_row.get(source_col) or "").strip()
        # Every account starts here. Sorting the sheet by next_touch_date is the
        # daily working view, so it must never be left as a stale value.
        row["status"] = "not_started"
        row["email_verified"] = "unchecked"
        row["opted_out"] = "no"
        yield row


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", help="CSV produced by adv_filter.py")
    parser.add_argument("--output", default="outbound_tracker.csv")
    parser.add_argument("--template-only", action="store_true",
                        help="write headers only, no input file required")
    args = parser.parse_args()

    if not args.template_only and not args.input:
        parser.error("--input is required unless --template-only is given")

    with open(args.output, "w", newline="", encoding="utf-8") as out_handle:
        writer = csv.DictWriter(out_handle, fieldnames=HEADER)
        writer.writeheader()

        if args.template_only:
            print(f"Wrote header-only tracker to {args.output}")
            print(f"Valid status values: {', '.join(STATUS_VALUES)}")
            return

        with open(args.input, newline="", encoding="utf-8-sig") as in_handle:
            reader = csv.DictReader(in_handle)
            resolved = resolve_columns(reader.fieldnames)
            count = 0
            for row in build_rows(reader, resolved):
                writer.writerow(row)
                count += 1

    print(f"Wrote {count} accounts to {args.output}")
    print(f"Valid status values: {', '.join(STATUS_VALUES)}")


if __name__ == "__main__":
    main()
