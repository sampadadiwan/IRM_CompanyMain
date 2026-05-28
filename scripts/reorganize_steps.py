#!/usr/bin/env python3
"""
Reorganizes fund.rb step definitions into model-specific files.

Block detection: a step begins at a Given/When/Then/And/But line and ends at
the first 'end' that has the SAME indentation as the step's opening line.
This correctly handles if/unless/case/begin blocks inside the step body (they
always have deeper indentation than the step's own closing 'end').
"""

import re
import os

STEP_DIR = '/home/thimmaiah/work/IRM/features/step_definitions'
FUND_RB  = os.path.join(STEP_DIR, 'fund.rb')

TARGETS = {
    'capital_call':         'capital_call.rb',
    'capital_distribution': 'capital_distribution.rb',
    'capital_commitment':   'capital_commitment.rb',
    'capital_remittance':   'capital_remittance.rb',
    'account_entries':      'account_entries.rb',
    'fund_unit':            'fund_unit.rb',
    'fund_ratio':           'fund_ratio.rb',
    'fund':                 'fund.rb',
}

# Classification rules — ORDER MATTERS: first match wins.
RULES = [
    # Capital Distribution — check before capital_call to handle overlap
    # Note: 'distrbution' (missing 'i') is a typo used consistently in fund.rb
    (r'capital\s*distrib|distrbution|distribution\s*payment|dist\s*payment|'
     r'dist\s*notice|distribution\s*notice|distribution\s*template|'
     r'dist\s*template|distribution\s*is\s*approved|capital\s*distribution\s*payment|'
     r'given\s+i\s+upload.*distributions|upload.*for\s+distributions|'
     r'upload.*for\s+the\s+distribution\s+payments|'
     r'dist\s*payments\s*are|dist\s*notice\s*is|dist\s*notice\s*must|'
     r'notification.*distribution\s*notice|dist\s*payments\s*have\s*proper|'
     r'trigger\s*notification\s*for\s*the\s*distribution|'
     r'distribution\s*is\s*not\s*manually|'
     r'new\s*capital\s*distribution\s*payments\s*must|'
     r'generated\s*distribution\s*notices|'
     r'capital\s*distribution\s*payments\s*are\s*approved|'
     r'fund\s*has\s*a\s*distribution\s*template|'
     r'proper\s*documents.*commitments\s*and\s*distributions|'
     r'commitment\s*and\s*distribuition\s*docs',
     'capital_distribution'),

    # Capital Call — check before capital_commitment and capital_remittance
    (r'capital\s*call|'
     r'remittances\s*generated\s*for\s*the\s*capital|'
     r'call\s*notice|call\s*template|'
     r'capital\s*remittance\s*whatsapp|'
     r'no\s*capital\s*remittances\s*should|'
     r'upload.*for\s*(the\s*)?remittances\s*of\s*the\s*capital\s*call|'
     r'remittance\s*payments\s*must\s*have|'
     r'remittance\s*payments\s*created|'
     r'upload.*call\s*remittances|'
     r'capital\s*call\s*collected|'
     r'remittance\s*rollups\s*should|'
     r'mark\s*the\s*remittances\s*as|'
     r'remittances\s*must\s*be\s*marked|'
     r'recompute\s*the\s*capital\s*call|'
     r'proper\s*fees\s*and\s*call\s*amount|'
     r'updated\s*proper\s*fees|'
     r'remittance\s*have\s*a\s*document|'
     r'notification.*remittance\s*investors|'
     r'custom\s*notification.*for\s*the\s*call|'
     r'notification.*call\s*notice|'
     r'approve\s*the\s*capital\s*call|'
     r'remittances\s*have\s*proper\s*notification|'
     r'remittance\s*notice\s*must\s*be\s*generated|'
     r'call\s*notice\s*is\s*generated|'
     r'update.*remittances\s*commitments\s*custom\s*fields|'
     r'proper\s*documents.*for\s*the\s*remittances|'
     r'remittance\s*docs\s*upload\s*errors|'
     r'remittance\s*payments\s*upload\s*errors|'
     r'generated\s*call\s*notices|'
     r'if\s*the\s*last\s*remittance\s*payment\s*is\s*deleted|'
     r'if\s*the\s*first\s*remittance\s*is\s*deleted|'
     r'there\s*should\s*be.*remittance\s*payments\s*created|'
     r'there\s*should\s*be.*capital\s*calls\s*created|'
     r'capital\s*calls\s*must\s*have\s*the\s*data|'
     r'no\s*remittances\s*should|'
     r'corresponding\s*remittances\s*should|'
     r'see\s*the\s*remittances\b|'
     r'doc.*attached.*capital\s*remittanc',
     'capital_call'),

    # Capital Remittance — standalone remittance operations
    (r'remittances\s*are\s*paid\b|'
     r'remittances\s*are\s*overpaid|'
     r'remittances\s*are\s*verified\b|'
     r'remittances\s*have\s*verified|'
     r'convert_to_fund_currency|'
     r'remittance\s*payment\s*amount|'
     r'payments\s*for\s*each\s*remittance|'
     r'remittances\s*are\s*paid.*and\s*verified|'
     r'see\s*my\s*capital\s*remittances',
     'capital_remittance'),

    # Capital Commitment
    (r'capital\s*commitment|'
     r'commitment\s*adjustment|'
     r'kyc\s*linked\s*to\s*the\s*commitment|'
     r'commitments\s*from\s*each\s*investor|'
     r'commitment\s*is\s*resaved|'
     r'commitments\s*have\s*a\s*cc|'
     r'adjustment\s*is\s*destroyed|'
     r'commitment\s*amounts\s*change|'
     r'fund\s*total\s*committed\s*amount|'
     r'see\s*my\s*capital\s*commitments|'
     r'lp\s*and\s*gp\s*commitments|'
     r'each\s*investor\s*has\s*a.*kyc|'
     r'commitments\s*have\s*investor\s*kycs|'
     r'multiple\s*commitments\s*have|'
     r'last\s*remittance\s*should\s*have\s*a\s*arrears|'
     r'reverse\s*remittance\s*payment\s*must|'
     r'collected\s*amounts\s*must\s*be\s*computed',
     'capital_commitment'),

    # Fund Unit — check BEFORE account_entries so transfer-related AE steps go here
    (r'fund\s*unit\s*setting|'
     r'fund\s*has\s*fund\s*units|'
     r'units\s*are\s*generated|'
     r'units\s*should\s*be\s*transferred|'
     r'units\s*for\s*the\s*calls\s*payment|'
     r'units\s*for\s*the\s*distribution\s*payments|'
     r'total\s*units\s*should|'
     r'units\s*created\s*with\s*data|'
     r'fund\s*units\s*are\s*transferred|'
     r'excluded\s*account\s*entry\s*is\s*copied|'
     r'other\s*account\s*entries\s*are\s*pro|'
     r'unit\s*counter\s*caches|'
     r'fund\s*units\s*are\s*fully|'
     r'units\s*generated\s*for\s*the\s*latest|'
     r'total\s*units\s*should\s*match|'
     r'upload.*fund\s*units\s*of\s*the|'
     r'there\s*should\s*be.*fund\s*units\s*created|'
     r'see\s*the\s*transferred\s*fund\s*units|'
     r'fund\s*units\s*are\s*transferred\s*with\s*ratio|'
     r'not\s*affected\s*by\s*the\s*transfer|'
     r'fund\s*unit\s*setting\s*associated|'
     r'upon\s*fund\s*unit\s*transfer|'
     r'adjusted\s*upon\s*fund',
     'fund_unit'),

    # Account Entry
    (r'account[\s_]*entries|account_entries',
     'account_entries'),

    # Fund Ratio / Formula
    (r'fund\s*formula|'
     r'fund\s*ratio|'
     r'upload.*fund\s*formula',
     'fund_ratio'),
]


def classify(step_text: str) -> str:
    lower = step_text.lower()
    for pattern, target in RULES:
        if re.search(pattern, lower):
            return target
    return 'fund'


def parse_blocks(raw: str):
    """
    Split fund.rb into:
      header: lines before the first step
      blocks:  list of {step_text, lines, target}

    Block detection uses INDENTATION:
    A step starts at a Given/When/Then/And/But line.
    The step ends at the first 'end' with the same indentation as the step start.
    This handles if/unless/case/begin blocks inside the body — they are always
    more deeply indented than the step's own 'end'.
    """
    lines = raw.splitlines(keepends=True)
    step_start_re = re.compile(r'^(\s*)(Given|When|Then|And|But)\s*\(')

    header = []
    blocks = []
    current_lines = None
    step_text = None
    step_indent = None   # string of leading whitespace on the step's first line
    closing_end = None   # the exact string that closes this block, e.g. '  end'

    for line in lines:
        if current_lines is None:
            # Not inside a block: check for step start
            m = step_start_re.match(line)
            if m:
                step_indent_str = m.group(1)   # leading whitespace
                closing_end = step_indent_str + 'end'

                # Extract step text from quoted arg
                tm = re.search(r"(?:Given|When|Then|And|But)\s*\('([^']*)'", line)
                if not tm:
                    tm = re.search(r'(?:Given|When|Then|And|But)\s*\("([^"]*)"', line)
                step_text = tm.group(1) if tm else line.strip()

                current_lines = [line]
            else:
                header.append(line)
        else:
            # Inside a block
            current_lines.append(line)
            # Check for closing 'end': the rstripped line must equal closing_end
            rstripped = line.rstrip('\n\r')
            if rstripped == closing_end:
                # Block is complete
                blocks.append({
                    'step_text': step_text,
                    'lines': current_lines,
                })
                current_lines = None
                step_text = None
                step_indent = None
                closing_end = None

    # Flush any unclosed block (shouldn't happen in valid Ruby)
    if current_lines:
        print(f"WARNING: unclosed block for step '{step_text}'")
        blocks.append({'step_text': step_text, 'lines': current_lines})

    # Classify
    for b in blocks:
        b['target'] = classify(b['step_text'])

    return header, blocks


def main():
    with open(FUND_RB, 'r') as f:
        raw = f.read()

    header, blocks = parse_blocks(raw)

    # Sanity check: verify no step text appears more than once
    seen = {}
    for b in blocks:
        key = b['step_text']
        seen.setdefault(key, 0)
        seen[key] += 1
    dupes = {k: v for k, v in seen.items() if v > 1}
    if dupes:
        print("WARNING: duplicate step texts detected:")
        for k, v in dupes.items():
            print(f"  {v}x '{k}'")

    # Group by target
    by_target = {}
    for b in blocks:
        by_target.setdefault(b['target'], []).append(b)

    # Summary
    print("=== Classification Summary ===")
    for target in sorted(by_target.keys()):
        print(f"\n-- {target} ({len(by_target[target])} steps) --")
        for b in by_target[target]:
            print(f"   '{b['step_text']}'")

    total = sum(len(v) for v in by_target.values())
    print(f"\nTotal step blocks: {total} (header lines: {len(header)})")

    # Write output files
    print("\n=== Writing files ===")

    for target_key, filename in TARGETS.items():
        target_blocks = by_target.get(target_key, [])
        filepath = os.path.join(STEP_DIR, filename)

        if target_key == 'fund':
            if not target_blocks:
                print(f"No fund blocks — skipping rewrite of {filename}")
                continue
            # Rewrite fund.rb: header + fund-only blocks
            content = ''.join(header)
            for b in target_blocks:
                content += ''.join(b['lines'])
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Rewrote {filename}: {len(target_blocks)} steps kept, "
                  f"{sum(len(b['lines']) for b in target_blocks)} lines")
        else:
            if not target_blocks:
                print(f"No blocks for {target_key} — skipping {filename}")
                continue
            # Append to existing file (or create)
            new_content = '\n' + ''.join(
                '\n' + ''.join(b['lines']) if not ''.join(b['lines']).startswith('\n') else ''.join(b['lines'])
                for b in target_blocks
            )
            if os.path.exists(filepath):
                with open(filepath, 'a') as f:
                    f.write(new_content)
                print(f"Appended to {filename}: {len(target_blocks)} steps")
            else:
                with open(filepath, 'w') as f:
                    f.write(new_content.lstrip('\n'))
                print(f"Created {filename}: {len(target_blocks)} steps")


if __name__ == '__main__':
    main()
