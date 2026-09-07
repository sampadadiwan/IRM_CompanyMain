# Extracts the depositor's name and (when the bank's narration format includes it)
# account number from a raw bank statement narration ("Transaction Remarks" / "Particulars")
# for a credit/deposit row. Different banks (and different transfer rails - RTGS, NEFT, IMPS,
# cheque clearing, mobile transfer...) format this text differently and some simply never
# include the remitter's account number, so `account_number` is legitimately nil far more
# often than not - callers must not treat a nil account as a parse failure.
#
# Every remittance rail this was built against also produces "deposits" that aren't external
# investor money at all - fixed-deposit maturities/rollovers, loan/OD credits, closure proceeds
# sweeping back into the operating account. Those come back with `internal: true` and should be
# excluded from investor-matching rather than surfaced as an unmatched depositor.
#
# Narration format is a property of *which bank issued the statement*, not of which fund/entity
# uploaded it, so parsing is split into a registry of per-bank modules (IciciNarrationParser,
# AxisNarrationParser, ...) under bank_deposit_narration_parser/ plus a FallbackNarrationParser
# for narration shapes common enough across banks' core-banking templates (slash-style
# RTGS/NEFT, bare TRF/) to serve as a first guess for a bank with no dedicated module yet. Each
# bank module implements its own `.parse(text) -> Result`, always falling through to
# FallbackNarrationParser, which always falls through to `unparsed`, so every bank module's
# `.parse` is total - it never returns nil.
#
# These are flat top-level modules (IciciNarrationParser, not BankDepositNarrationParser::Icici)
# - this app's autoload config treats every directory under services/ as its own Zeitwerk root
# (see services/chat_providers/, services/digio/ for precedent), so a nested-namespace constant
# under bank_deposit_narration_parser/ would never resolve.
#
# Usage:
#   bank = BankDepositNarrationParser.detect_bank(sheet)        # => IciciNarrationParser
#   result = bank.parse(row["Transaction Remarks"])
#   result.name            # => "ROHIT AGARWAL" or nil
#   result.account_number  # => "50100347871421" or nil
#   result.confidence      # => :high / :medium / :low / :none
#   result.internal        # => true for the fund's own FD/loan movements
#   result.notes           # => human-readable caveat, or nil
module BankDepositNarrationParser
  Result = Struct.new(:raw, :name, :account_number, :pattern, :confidence, :internal, :notes, keyword_init: true)

  module_function

  # IFSC's first 4 letters are the bank code. Each statement's header/footer carries its own
  # account's IFSC (e.g. "A/C No: 000405651845    IFSC: ICIC0000004") - the bank is identified
  # once per sheet from that, never re-derived per row from a narration's *embedded* IFSC
  # (which just as often names the *remitter's* bank, not the statement issuer).
  #
  def bank_modules
    { 'ICIC' => IciciNarrationParser, 'UTIB' => AxisNarrationParser } # Axis Bank, fka UTI Bank - IFSC prefix predates the rebrand
  end

  # Backward-compatible top-level entry point for a caller that hasn't resolved a bank module
  # yet (e.g. an ad-hoc one-off narration with no sheet context). Prefer `detect_bank(sheet)`
  # + `bank.parse(remark)` when a sheet is available, since that's what actually picks the
  # right bank-specific patterns; this degrades to the shared generic ones only.
  def parse(remark, bank_module: FallbackNarrationParser)
    bank_module.parse(remark.to_s.strip)
  end

  def unparsed(text)
    Result.new(raw: text, name: nil, account_number: nil, pattern: 'UNMATCHED',
               confidence: :none, internal: false, notes: 'no known narration pattern matched; needs manual review')
  end

  # Scans the first few rows of a sheet's account-statement header for "IFSC: XXXX..." and
  # maps the 4-letter bank code to its parser module. Falls back to FallbackNarrationParser
  # (not an error) for a bank with no dedicated module yet - a new statement export should
  # still parse via whatever generic patterns apply, not block entirely on an unrecognized
  # IFSC prefix.
  def detect_bank(sheet)
    (1..[sheet.last_row, 10].min).each do |r|
      sheet.row(r).each do |cell|
        m = cell.to_s.match(/IFSC:\s*([A-Z]{4})/)
        return bank_modules[m[1]] || FallbackNarrationParser if m
      end
    end
    FallbackNarrationParser
  end

  # Console/manual-test helper: reads every deposit narration out of a bank statement xlsx
  # (handles both the "Transaction Remarks" + "Deposit (Cr)" layout and the "Particulars" +
  # "Debit/Credit" layout seen so far) and prints what this parser extracts from each one, so a
  # new statement export can be sanity-checked without wiring up any import feature. Run from
  # `bin/rails console`:
  #
  #   BankDepositNarrationParser.test_extraction("~/Downloads/Bank_Statements_Jun26.xlsx")
  # rubocop:disable Rails/Output -- intentional console printer, not application logging
  def test_extraction(path)
    require 'roo'
    xlsx = Roo::Spreadsheet.open(File.expand_path(path))

    xlsx.sheets.each do |sheet_name|
      sheet = xlsx.sheet(sheet_name)
      header_row_index, headers = find_header_row(sheet)
      next unless headers

      bank = detect_bank(sheet)
      narration_col_name = headers.include?('Transaction Remarks') ? 'Transaction Remarks' : 'Particulars'
      entries = each_deposit_narration(sheet, header_row_index: header_row_index, headers: headers)
      next if entries.empty?

      puts '=' * 100
      puts "#{sheet_name} (#{entries.size} deposits) - bank #{bank} - narration column '#{narration_col_name}' (header row #{header_row_index})"
      puts '=' * 100
      puts 'Row    | Name                                          | Account #          | Conf    | Pattern        | Notes'

      rows = entries.map { |entry| [entry[:row], bank.parse(entry[:remark].to_s.strip)] }
      fill_in_llm_explanations!(rows)

      rows.each do |row_num, result|
        notes = [result.internal ? '(internal)' : nil, result.notes].compact.join(' ')
        puts format('%-6s | %-45s | %-18s | %-7s | %-14s | %s',
                    row_num,
                    (result.name || '-')[0, 45],
                    result.account_number || '-',
                    result.confidence,
                    result.pattern,
                    notes)
      end
    end
    nil
  end
  # rubocop:enable Rails/Output

  # For every UNMATCHED row (no known narration pattern fired), asks an LLM - in a single
  # batched call, not one per row - to explain what payment rail the narration looks like it
  # came from and why it couldn't be auto-parsed. Best-effort: mutates each result's `notes`
  # in place only where the LLM produced an explanation, and is a no-op (including when the
  # LLM call fails) if there's nothing UNMATCHED to explain.
  def fill_in_llm_explanations!(rows)
    unmatched = rows.select { |_row_num, result| result.pattern == 'UNMATCHED' }
    return if unmatched.empty?

    explanations = NarrationMissExplainer.call(narrations: unmatched.map { |_row_num, result| result.raw })[:explanations] || {}
    unmatched.map(&:last).each { |result| result.notes = explanations[result.raw] if explanations[result.raw] }
  end

  # Scans the first 15 rows for the header row (identified by the narration column's header
  # cell) and returns [row_index, header_cells], or nil if neither known layout is found.
  def find_header_row(sheet)
    (1..[sheet.last_row, 15].min).each do |r|
      row = sheet.row(r)
      return [r, row] if row.include?('Transaction Remarks') || row.include?('Particulars')
    end
    nil
  end

  # Pulls out one Hash per row that is a real deposit -- skips totals/summary footer rows
  # (identified by the serial-number column not being numeric there) and withdrawal rows.
  # {row:, remark:, amount:, tran_id:, value_date:} -- `amount` is nil only when the sheet has
  # neither a "Deposit (Cr)" nor an "Amount (INR)" column at all (an unrecognized layout).
  # `tran_id` (the bank's own transaction id) is only present on banks with a "Tran Id" column
  # (observed: ICICI) - nil elsewhere, since not every bank statement export exposes one.
  def each_deposit_narration(sheet, header_row_index: nil, headers: nil)
    header_row_index, headers = find_header_row(sheet) if headers.nil?
    return [] unless headers

    sl_col = headers.index('Sl No') || headers.index('S.No')
    narration_col = headers.index('Transaction Remarks') || headers.index('Particulars')
    deposit_col = headers.index('Deposit (Cr)')
    drcr_col = headers.index('Debit/Credit')
    # Neither column present means this layout has no way to tell a deposit from a withdrawal
    # at all - bail out rather than fall through to `row[nil] == 'CR'`, which would raise.
    return [] if deposit_col.nil? && drcr_col.nil?

    amount_col = deposit_col || headers.index('Amount (INR)')
    tran_id_col = headers.index('Tran Id')
    date_col = headers.index('Value Date') || headers.index('Transaction Date')

    ((header_row_index + 1)..sheet.last_row).filter_map do |r|
      row = sheet.row(r)
      next if sl_col && !row[sl_col].is_a?(Numeric) # skip TOTAL/opening-balance/footer rows

      remark = row[narration_col]
      next unless remark

      is_deposit = deposit_col ? !row[deposit_col].nil? : row[drcr_col] == 'CR'
      next unless is_deposit

      {
        row: r,
        remark: remark,
        amount: amount_col ? parse_statement_amount(row[amount_col]) : nil,
        tran_id: tran_id_col ? row[tran_id_col].to_s.strip.presence : nil,
        value_date: date_col ? parse_statement_date(row[date_col]) : nil
      }
    end
  end

  # Amount cells are normally numeric (Roo hands back a Float for a real number cell), but some
  # exports write them as text with Indian digit grouping ("6,99,842.06") - a bare `to_f` on
  # that string silently yields 6.0, which would then be scored as a wildly short payment.
  # Strip grouping separators and whitespace first; anything still non-numeric returns nil
  # (the agent reports "no readable amount") rather than a wrong number.
  def parse_statement_amount(value)
    return value.to_f if value.is_a?(Numeric)

    str = value.to_s.delete(',').delete("\u20B9").strip # also drop a stray rupee sign
    return nil if str.empty?

    str.match?(/\A-?\d+(\.\d+)?\z/) ? str.to_f : nil
  end

  # Bank statement date cells arrive as either a genuine Date/DateTime (Roo parses a real
  # Excel date cell automatically) or literal text in one of two formats seen so far:
  # ICICI's "05/Jun/2026" (day/month-name/year, unambiguous) and Axis's "02/06/2026"
  # (day/month/year - NOT US month/day/year, so plain Date.parse would silently misparse
  # e.g. "02/06/2026" as Feb 6 instead of Jun 2). Tried explicitly in that order; returns nil
  # rather than raising for anything else, since a missing payment_date should never block
  # the rest of the pipeline.
  def parse_statement_date(value)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    str = value.to_s.strip
    return nil if str.empty?

    begin
      Date.strptime(str, '%d/%b/%Y')
    rescue ArgumentError, TypeError
      begin
        Date.strptime(str, '%d/%m/%Y')
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
