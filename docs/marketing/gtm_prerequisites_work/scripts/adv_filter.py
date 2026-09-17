#!/usr/bin/env python3
"""
adv_filter.py -- Size the CapHive US ICP from SEC Form ADV bulk data.

WHAT THIS DOES
--------------
Downloads (or reuses) the SEC's monthly "Information About Registered Investment
Advisers" bulk ZIP, parses it, and counts how many SEC-registered investment
advisers match the CapHive ICP:

  * Regulatory Assets Under Management (RAUM, Form ADV Item 5.F.(2)(c))
    between $300M and $2B (inclusive, configurable), AND
  * 3 or more private fund vehicles (Form ADV Schedule D Section 7.B.(1)).

It prints funnel counts + a fund-count histogram + complexity signals, and writes
the matching firms to a CSV for outbound work.

WHY THE URL HANDLING LOOKS LIKE THIS
------------------------------------
The SEC publishes this data in two places and the layout drifts constantly:

  1. https://www.sec.gov/files/investment/data/...  (WORKS from most networks)
  2. https://reports.adviserinfo.sec.gov/reports/CompilationReports/ia*.zip
     (sits behind Cloudflare; returns 403 to non-browser clients as of 2026-08)

So this script scrapes the SEC landing page for the newest `ia<MMDDYY>.zip`
rather than hardcoding a URL that will rot. A pinned fallback URL is used if
discovery fails. The SEC requires a descriptive User-Agent with contact info on
all automated requests -- see SEC_USER_AGENT below.

TWO ZIP LAYOUTS ARE SUPPORTED
-----------------------------
  (a) "Firm roster" layout (current, e.g. ia060126_0.zip): ONE wide CSV with a
      row per adviser, including a precomputed `Count of Private Funds - 7B(1)`
      column plus per-fund-type counts.
  (b) "Multi-file" layout (older / the adviserinfo Form ADV Data set): a base
      CSV (IA_ADV_Base_A_*.csv) plus a separate Schedule D 7.B.(1) CSV with one
      row per private fund, which we group-count by filing/CRD id.

Column names drift between vintages, so every column is resolved through
`resolve_column()`, which matches case-insensitively against a list of candidate
names and FAILS LOUDLY with the full header list if nothing matches.

USAGE
-----
  # Everything default: discover newest ZIP, download, analyze
  python3 adv_filter.py

  # Reuse an already-downloaded zip, custom thresholds
  python3 adv_filter.py --zip tmp/adv_data/ia060126_0.zip \
      --min-raum 300e6 --max-raum 2e9 --min-funds 3

  # Include Exempt Reporting Advisers file instead
  python3 adv_filter.py --url https://www.sec.gov/files/.../ia060126-exempt.zip
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import re
import sys
import zipfile
from collections import Counter, defaultdict
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The SEC's automated-access policy requires a User-Agent identifying the
# requester with contact info. Requests without one get 403'd.
SEC_USER_AGENT = "CapHive Research thimmaiah@gmail.com"

# Landing page that lists every monthly bulk ZIP. Scraped to find the newest.
SEC_LISTING_URL = (
    "https://www.sec.gov/data-research/sec-markets-data/"
    "information-about-registered-investment-advisers-exempt-reporting-advisers"
)

# Fallback if scraping the listing page fails (verified working 2026-08-16).
PINNED_FALLBACK_URL = (
    "https://www.sec.gov/files/investment/data/other/"
    "information-about-registered-investment-advisers-exempt-reporting-advisers/"
    "ia060126_0.zip"
)

DEFAULT_OUTDIR = os.path.join("tmp", "adv_data")

# ---- Candidate column names, most-preferred first -------------------------
# Each entry is a list of names the SEC has used (or plausibly uses) for the
# same logical field across vintages. Matching is case/space/punctuation-loose.
COLUMN_CANDIDATES = {
    "raum": [
        "5F(2)(c)",              # current firm-roster layout: total RAUM
        "5.F.(2)(c)",
        "Item 5.F.(2)(c)",
        "Total_RAUM",
        "Total RAUM",
        "RAUM",
    ],
    "fund_count": [
        "Count of Private Funds - 7B(1)",   # current firm-roster layout
        "Count of Private Funds 7B(1)",
        "7B(1)",
        "7.B.(1)",
        "Total number of private funds",
        "Private Fund Count",
    ],
    "firm_name": [
        "Primary Business Name",
        "Legal Name",
        "Business Name",
        "1A",
    ],
    "crd": [
        "Organization CRD#",
        "Organization CRD Number",
        "CRD Number",
        "CRD#",
        "1E1",
    ],
    "state": [
        "Main Office State",
        "1F(1)-State",
        "State",
    ],
    "city": ["Main Office City", "1F(1)-City", "City"],
    "country": ["Main Office Country", "1F(1)-Country", "Country"],
    "website": [
        "Website Address",
        "Website",
        "1I-Website",
    ],
    "phone": [
        "Main Office Telephone Number",
        "Telephone Number",
        "1J-Phone",
    ],
    "sec_status": ["SEC Current Status", "Current Status", "Status"],
    "firm_type": ["Firm Type"],
    "latest_filing": ["Latest ADV Filing Date", "Date Submitted", "DateSubmitted"],
    "gross_pf_assets": [
        "Total Gross Assets of Private Funds",
        "Total Gross Asset Value of Private Funds",
    ],
    "employees": ["5A", "5.A."],
    "sma_clients": ["5C(1)", "5.C.(1)"],
}

# Per-fund-type count columns used for the "complexity" bonus analysis.
# Key = human label, value = candidate column names.
FUND_TYPE_COUNT_CANDIDATES = {
    "Hedge": ["Total number of Hedge funds", "Total number of Hedge Funds"],
    "PE": ["Total number of PE funds", "Total number of PE Funds"],
    "Real Estate": ["Total number of Real Estate funds"],
    "VC": ["Total number of VC funds"],
    "Liquidity": ["Total number of Liquidity funds"],
    "Securitized": ["Total number of Securitized funds"],
    "Other": ["Total number of Other funds"],
}

# Columns in the separate Schedule D 7.B.(1) CSV (multi-file layout) that
# identify which adviser a private-fund row belongs to.
SCHEDULE_D_JOIN_CANDIDATES = [
    "Filing ID", "FilingID", "1E1", "Organization CRD#", "CRD Number", "CRD#",
]


# ---------------------------------------------------------------------------
# Column resolution -- tolerant of SEC header drift
# ---------------------------------------------------------------------------

def _normalize(name: str) -> str:
    """Lowercase and strip everything that isn't alphanumeric.

    SEC headers vary by case, punctuation ('7B(1)' vs '7.B.(1)'), embedded
    newlines, and stray whitespace. Normalizing to bare alphanumerics makes all
    those variants compare equal.
    """
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def resolve_column(header, candidates, logical_name, required=True):
    """Return the actual header string matching one of `candidates`.

    Tries exact normalized match first, then a normalized 'contains' match.
    Raises SystemExit with the FULL header list when a required column is
    missing -- deliberately loud, because a silently-missing RAUM column would
    produce a plausible-looking but wrong ICP number.
    """
    norm_header = {_normalize(h): h for h in header}

    # Pass 1: exact normalized equality, in candidate preference order.
    for cand in candidates:
        hit = norm_header.get(_normalize(cand))
        if hit is not None:
            return hit

    # Pass 2: substring match (handles e.g. '5F(2)(c) - Total' style suffixes).
    for cand in candidates:
        n = _normalize(cand)
        if not n:
            continue
        for hn, orig in norm_header.items():
            if n == hn or (len(n) >= 4 and n in hn):
                return orig

    if not required:
        return None

    sys.exit(
        "\nFATAL: could not locate the '{}' column.\n"
        "  Tried these candidate names: {}\n"
        "  The SEC renames columns between vintages -- add the correct name to\n"
        "  COLUMN_CANDIDATES['{}'] in this script.\n\n"
        "  ACTUAL HEADERS PRESENT ({} columns):\n{}\n".format(
            logical_name,
            candidates,
            logical_name,
            len(header),
            "\n".join("    [{}] {!r}".format(i, h) for i, h in enumerate(header)),
        )
    )


# ---------------------------------------------------------------------------
# Value parsing
# ---------------------------------------------------------------------------

def parse_money(raw):
    """Parse SEC money strings like '   578,062,390.00' -> 578062390.0.

    Returns None for blanks/unparseable so callers can distinguish 'no answer'
    from a genuine zero.
    """
    if raw is None:
        return None
    s = str(raw).strip().replace(",", "").replace("$", "")
    if not s:
        return None
    neg = s.startswith("(") and s.endswith(")")   # accounting-style negatives
    if neg:
        s = s[1:-1]
    try:
        val = float(s)
    except ValueError:
        return None
    return -val if neg else val


def parse_int(raw):
    """Parse a right-padded integer string like '                   3' -> 3."""
    if raw is None:
        return None
    s = str(raw).strip().replace(",", "")
    if not s:
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Download / discovery
# ---------------------------------------------------------------------------

def http_get(url, timeout=300):
    """GET with the SEC-required User-Agent and gzip-friendly headers."""
    req = Request(
        url,
        headers={
            "User-Agent": SEC_USER_AGENT,
            "Accept-Encoding": "gzip, deflate",
            "Accept": "*/*",
            "Host": re.sub(r"^https?://([^/]+).*$", r"\1", url),
        },
    )
    with urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    # urllib does not auto-decompress; handle gzip if the server used it.
    if data[:2] == b"\x1f\x8b":
        import gzip
        data = gzip.decompress(data)
    return data


def discover_latest_url():
    """Scrape the SEC listing page for the newest non-exempt ia<MMDDYY>.zip.

    Returns None on any failure so the caller can fall back to the pinned URL.
    NOTE: the containing directory literally contains the word 'exempt'
    ('...registered-investment-advisers-exempt-reporting-advisers/'), so the
    exempt/non-exempt test MUST be applied to the basename only.
    """
    try:
        html = http_get(SEC_LISTING_URL, timeout=60).decode("utf-8", "replace")
    except Exception as exc:                      # network down, 403, etc.
        print("  [discover] listing page fetch failed: {}".format(exc))
        return None

    best = None  # (sortable_yymmdd, url)
    for path in re.findall(r'"(/[^"]*?/ia\d{6}[^"/]*?\.zip)"', html):
        base = path.rsplit("/", 1)[-1]
        if "exempt" in base.lower():              # skip the ERA-only file
            continue
        m = re.match(r"ia(\d{2})(\d{2})(\d{2})", base)
        if not m:
            continue
        mm, dd, yy = m.groups()
        key = (yy, mm, dd)                        # YY-MM-DD sorts correctly
        if best is None or key > best[0]:
            best = (key, "https://www.sec.gov" + path)

    if best:
        print("  [discover] newest bulk file on SEC listing: {}".format(best[1]))
        return best[1]
    print("  [discover] no ia*.zip links found on listing page")
    return None


def fetch_zip(url, outdir):
    """Download `url` into `outdir` unless already present. Returns local path."""
    os.makedirs(outdir, exist_ok=True)
    local = os.path.join(outdir, url.rsplit("/", 1)[-1])
    if os.path.exists(local) and os.path.getsize(local) > 0:
        print("  [download] reusing cached {} ({:,} bytes)".format(
            local, os.path.getsize(local)))
        return local
    print("  [download] GET {}".format(url))
    data = http_get(url)
    with open(local, "wb") as fh:
        fh.write(data)
    print("  [download] wrote {} ({:,} bytes)".format(local, len(data)))
    return local


# ---------------------------------------------------------------------------
# ZIP / CSV loading
# ---------------------------------------------------------------------------

def _read_csv_from_zip(zf, name):
    """Read one CSV member into (header_list, list_of_dicts)."""
    with zf.open(name) as raw:
        # utf-8-sig strips the BOM the SEC ships; errors='replace' survives the
        # stray latin-1 bytes that appear in a handful of firm names.
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace",
                                newline="")
        reader = csv.reader(text)
        header = next(reader)
        rows = [dict(zip(header, r)) for r in reader]
    return header, rows


def load_tables(zip_path):
    """Return (header, base_rows, schedule_d_rows_or_None).

    Handles both ZIP layouts described in the module docstring.
    """
    with zipfile.ZipFile(zip_path) as zf:
        members = [n for n in zf.namelist()
                   if n.lower().endswith(".csv") and not n.startswith("__MACOSX")]
        if not members:
            sys.exit("FATAL: no CSV members in {}. Contents: {}".format(
                zip_path, zf.namelist()))

        # Identify the separate Schedule D 7.B.(1) file, if this vintage has one.
        sched_name = next(
            (n for n in members
             if re.search(r"7[_\- ]?b[_\- ]?\(?1\)?", n, re.I)
             or "schedule_d_7b1" in n.lower().replace("-", "_")),
            None,
        )
        # The base file is the largest remaining CSV (roster / Base_A).
        base_candidates = [n for n in members if n != sched_name]
        if not base_candidates:
            sys.exit("FATAL: only a Schedule D file found in {}".format(zip_path))
        base_name = max(base_candidates, key=lambda n: zf.getinfo(n).file_size)

        print("  [zip] base CSV      : {}".format(base_name))
        print("  [zip] schedule D 7B1: {}".format(sched_name or "(none - single-file layout)"))

        header, base_rows = _read_csv_from_zip(zf, base_name)
        sched_rows = None
        if sched_name:
            _, sched_rows = _read_csv_from_zip(zf, sched_name)

    return header, base_rows, sched_rows


def fund_counts_from_schedule_d(sched_rows, base_header):
    """Group the one-row-per-private-fund Schedule D table into {join_key: count}."""
    if not sched_rows:
        return None
    sched_header = list(sched_rows[0].keys())
    join_col = resolve_column(sched_header, SCHEDULE_D_JOIN_CANDIDATES,
                              "schedule-D join key")
    counts = Counter()
    for row in sched_rows:
        key = (row.get(join_col) or "").strip()
        if key:
            counts[key] += 1
    print("  [7B1] counted {:,} private-fund rows across {:,} advisers "
          "(join column {!r})".format(sum(counts.values()), len(counts), join_col))
    return counts, join_col


# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def analyze(args):
    # --- 1. Get the data ---------------------------------------------------
    if args.zip:
        zip_path = args.zip
        print("[1/4] Using local ZIP: {}".format(zip_path))
    else:
        url = args.url or discover_latest_url() or PINNED_FALLBACK_URL
        print("[1/4] Source URL: {}".format(url))
        zip_path = fetch_zip(url, args.outdir)

    # --- 2. Parse ----------------------------------------------------------
    print("[2/4] Parsing ZIP")
    header, rows, sched_rows = load_tables(zip_path)
    print("  [parse] {:,} adviser rows, {} columns".format(len(rows), len(header)))

    col = {}
    for key in ("raum", "firm_name", "crd"):
        col[key] = resolve_column(header, COLUMN_CANDIDATES[key], key)
    # Optional context columns -- absent ones just render blank in the output.
    for key in ("state", "city", "country", "website", "phone", "sec_status",
                "firm_type", "latest_filing", "gross_pf_assets", "employees",
                "sma_clients"):
        col[key] = resolve_column(header, COLUMN_CANDIDATES[key], key,
                                  required=False)

    # Fund count: prefer the separate Schedule D table (authoritative, one row
    # per fund); fall back to the precomputed base-file column.
    sched_lookup = None
    if sched_rows:
        sched_lookup = fund_counts_from_schedule_d(sched_rows, header)
    if sched_lookup:
        sched_counts, sched_join = sched_lookup
        base_join = resolve_column(header, SCHEDULE_D_JOIN_CANDIDATES,
                                   "base-file join key")
        fund_count_source = "Schedule D 7.B.(1) row counts"
    else:
        col["fund_count"] = resolve_column(header, COLUMN_CANDIDATES["fund_count"],
                                           "fund_count")
        sched_counts = base_join = None
        fund_count_source = "base-file column {!r}".format(col["fund_count"])
    print("  [parse] fund counts from: {}".format(fund_count_source))

    # Per-fund-type columns for the complexity bonus (all optional).
    type_cols = {}
    for label, cands in FUND_TYPE_COUNT_CANDIDATES.items():
        hit = resolve_column(header, cands, "fund type " + label, required=False)
        if hit:
            type_cols[label] = hit

    # --- 3. Filter ---------------------------------------------------------
    print("[3/4] Filtering: RAUM ${:,.0f}-${:,.0f}, >= {} private funds".format(
        args.min_raum, args.max_raum, args.min_funds))

    total = 0
    pass_aum = 0
    pass_funds = 0
    matches = []
    hist = Counter()                 # fund-count histogram, ALL advisers
    hist_in_aum = Counter()          # fund-count histogram, AUM-band advisers
    no_raum = 0
    type_mix = Counter()             # #distinct fund types among matches
    types_seen = Counter()           # which fund types matched firms run

    for row in rows:
        total += 1

        raum = parse_money(row.get(col["raum"]))
        if raum is None:
            no_raum += 1

        if sched_counts is not None:
            funds = sched_counts.get((row.get(base_join) or "").strip(), 0)
        else:
            funds = parse_int(row.get(col["fund_count"])) or 0

        hist[funds] += 1

        aum_ok = raum is not None and args.min_raum <= raum <= args.max_raum
        fund_ok = funds >= args.min_funds

        # Optional main-office-country filter. NOTE: every firm in this file is
        # SEC-*registered* regardless of domicile, so this narrows to US-
        # *domiciled* advisers -- a different (smaller) population.
        if args.country and col["country"]:
            if (row.get(col["country"]) or "").strip().lower() != args.country.strip().lower():
                continue
        if aum_ok:
            pass_aum += 1
            hist_in_aum[funds] += 1
        if fund_ok:
            pass_funds += 1
        if not (aum_ok and fund_ok):
            continue

        # --- complexity signals for matched firms ---
        per_type = {}
        for label, cname in type_cols.items():
            n = parse_int(row.get(cname)) or 0
            if n:
                per_type[label] = n
                types_seen[label] += 1
        n_types = len(per_type)
        type_mix[n_types] += 1

        matches.append({
            "firm_name": row.get(col["firm_name"], ""),
            "crd": (row.get(col["crd"]) or "").strip(),
            "raum_usd": int(raum),
            "private_fund_count": funds,
            "distinct_fund_types": n_types,
            "fund_type_mix": "; ".join(
                "{}={}".format(k, v) for k, v in sorted(per_type.items())),
            "gross_private_fund_assets": (
                parse_money(row.get(col["gross_pf_assets"])) if col["gross_pf_assets"] else None),
            "state": (row.get(col["state"]) or "").strip() if col["state"] else "",
            "city": (row.get(col["city"]) or "").strip() if col["city"] else "",
            "country": (row.get(col["country"]) or "").strip() if col["country"] else "",
            "website": (row.get(col["website"]) or "").strip() if col["website"] else "",
            "phone": (row.get(col["phone"]) or "").strip() if col["phone"] else "",
            "employees": (row.get(col["employees"]) or "").strip() if col["employees"] else "",
            "sec_status": (row.get(col["sec_status"]) or "").strip() if col["sec_status"] else "",
            "latest_adv_filing": (row.get(col["latest_filing"]) or "").strip() if col["latest_filing"] else "",
        })

    # --- 4. Report ---------------------------------------------------------
    print("\n" + "=" * 72)
    print("FORM ADV ICP FUNNEL   source={}".format(os.path.basename(zip_path)))
    print("=" * 72)
    if args.country:
        # 'Total advisers' and the all-adviser histogram stay unfiltered; the
        # funnel rows below are restricted to the chosen country.
        print("Country filter ACTIVE: {!r} (funnel rows below are country-scoped;\n"
              "  'Total advisers' and the all-adviser histogram are not)".format(
                  args.country))
    print("Total advisers in file                      : {:>8,}".format(total))
    print("  (rows with no/blank RAUM answer)          : {:>8,}".format(no_raum))
    print("Pass RAUM ${:,.0f} - ${:,.0f}{}: {:>8,}".format(
        args.min_raum, args.max_raum, " " * 8, pass_aum))
    print("Pass private funds >= {}                     : {:>8,}".format(
        args.min_funds, pass_funds))
    print("PASS BOTH  <-- ICP pool size                : {:>8,}".format(len(matches)))
    if total:
        print("                                              ({:.2f}% of all advisers)".format(
            100.0 * len(matches) / total))

    print("\n--- Private fund count histogram (all advisers) ---")
    _print_hist(hist, total)

    print("\n--- Private fund count histogram (advisers inside the AUM band) ---")
    _print_hist(hist_in_aum, pass_aum)

    if type_cols:
        print("\n--- Complexity signal: distinct private fund TYPES among the {:,} matches ---".format(
            len(matches)))
        for n in sorted(type_mix):
            print("  {} fund type(s) : {:>6,}  ({:.1f}%)".format(
                n, type_mix[n], 100.0 * type_mix[n] / max(len(matches), 1)))
        multi = sum(v for k, v in type_mix.items() if k >= 2)
        print("  --> multi-strategy (>=2 distinct fund types): {:,} ({:.1f}%)".format(
            multi, 100.0 * multi / max(len(matches), 1)))
        print("\n  Fund types run by matched firms (firms may run several):")
        for label, n in types_seen.most_common():
            print("    {:<14} {:>6,}".format(label, n))
    else:
        print("\n[note] No per-fund-type columns in this vintage; "
              "complexity breakdown skipped.")

    # Domicile split: SEC registration != US domicile, so show both.
    if col["country"]:
        print("\n--- Main-office country among matches ---")
        for ctry, n in Counter(m["country"] for m in matches).most_common(10):
            print("    {:<20} {:>5,}".format(ctry or "(blank)", n))

    # Geography is useful for outbound sequencing.
    if col["state"]:
        print("\n--- Top 15 states among matches ---")
        for st, n in Counter(m["state"] for m in matches).most_common(15):
            print("    {:<6} {:>5,}".format(st or "(blank)", n))

    # --- write CSV ---------------------------------------------------------
    out_csv = args.csv_out
    os.makedirs(os.path.dirname(os.path.abspath(out_csv)) or ".", exist_ok=True)
    fieldnames = [
        "firm_name", "crd", "raum_usd", "private_fund_count",
        "distinct_fund_types", "fund_type_mix", "gross_private_fund_assets",
        "state", "city", "country", "website", "phone", "employees",
        "sec_status", "latest_adv_filing",
    ]
    matches.sort(key=lambda m: (-m["private_fund_count"], -m["raum_usd"]))
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(matches)
    print("\n[4/4] Wrote {:,} matching firms -> {}".format(len(matches), out_csv))


def _print_hist(hist, denom):
    """Print a bucketed fund-count histogram."""
    buckets = [(0, 0), (1, 1), (2, 2), (3, 4), (5, 9), (10, 19), (20, 49),
               (50, 10 ** 9)]
    for lo, hi in buckets:
        n = sum(v for k, v in hist.items() if lo <= k <= hi)
        label = "{}".format(lo) if lo == hi else (
            "{}+".format(lo) if hi > 10 ** 8 else "{}-{}".format(lo, hi))
        pct = 100.0 * n / denom if denom else 0.0
        bar = "#" * int(pct / 2)
        print("  {:>7} funds : {:>7,}  {:>5.1f}%  {}".format(label, n, pct, bar))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(
        description="Count SEC-registered advisers matching the CapHive ICP "
                    "(RAUM band + private fund count) from Form ADV bulk data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--url", default=None,
                   help="Explicit bulk ZIP URL. Default: auto-discover the "
                        "newest ia*.zip from the SEC listing page, falling back "
                        "to a pinned URL.")
    p.add_argument("--zip", default=None,
                   help="Path to an already-downloaded ZIP; skips all network I/O.")
    p.add_argument("--outdir", default=DEFAULT_OUTDIR,
                   help="Download directory (default: %(default)s).")
    p.add_argument("--min-raum", type=float, default=300e6,
                   help="Minimum RAUM in USD (default: 300000000).")
    p.add_argument("--max-raum", type=float, default=2e9,
                   help="Maximum RAUM in USD (default: 2000000000).")
    p.add_argument("--min-funds", type=int, default=3,
                   help="Minimum private fund count (default: 3).")
    p.add_argument("--country", default=None,
                   help="Restrict matches to this main-office country, e.g. "
                        "'United States'. Default: no filter (all SEC "
                        "registrants, including foreign-domiciled ones).")
    p.add_argument("--csv-out", default=os.path.join(DEFAULT_OUTDIR,
                                                     "adv_icp_matches.csv"),
                   help="Output CSV path (default: %(default)s).")
    args = p.parse_args()

    if args.min_raum > args.max_raum:
        p.error("--min-raum must be <= --max-raum")

    analyze(args)


if __name__ == "__main__":
    main()
