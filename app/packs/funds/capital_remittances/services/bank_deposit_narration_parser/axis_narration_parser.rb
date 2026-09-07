# Axis narration formats — IMPS/P2A, MOB/TPFT, INB/IFT, "TRANSFER FROM <name>" (no colon,
# distinct from ICICI's "TRFR FROM:"), and the fund's own FD/loan movement narrations.
# Falls through to FallbackNarrationParser for the slash-delimited RTGS/NEFT and bare TRF/
# narrations Axis shares with other banks — handled once there, not duplicated.
#
# Flat top-level class, not BankDepositNarrationParser::Axis — see icici_narration_parser.rb
# for why (every services/ subdirectory here is its own Zeitwerk root).
module AxisNarrationParser
  module_function

  def parse(text)
    imps_p2a(text) ||
      mob_tpft(text) ||
      inb_ift(text) ||
      transfer_from(text) ||
      closure_proceeds(text) ||
      fd_internal(text) ||
      fd_internal_bare_numeric(text) ||
      loan_deposit(text) ||
      FallbackNarrationParser.parse(text)
  end

  # IMPS/P2A/<ref>/<name>/<bank>/<...>/<...>
  def imps_p2a(text)
    m = text.match(%r{\AIMPS/P2A/(?<ref>[^/]+)/(?<name>[^/]+)(?:/.*)?\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'IMPS-P2A',
                                           confidence: :low, internal: false,
                                           notes: 'IMPS name field is bank-truncated/abbreviated; trailing digits are a UTR/ref, not an account number')
  end

  # MOB/TPFT/<name>/<account>
  def mob_tpft(text)
    m = text.match(%r{\AMOB/TPFT/(?<name>[^/]+)/(?<account>\d{6,20})\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: m[:account], pattern: 'MOB-TPFT',
                                           confidence: :high, internal: false, notes: nil)
  end

  # INB/IFT/<name>/TPARTY TRANSFER
  def inb_ift(text)
    m = text.match(%r{\AINB/IFT/(?<name>[^/]+)/.*\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'INB-IFT',
                                           confidence: :medium, internal: false, notes: 'no account number present in this narration format')
  end

  # TRANSFER FROM <name>  (no colon — distinct from ICICI's "TRFR FROM:<name>")
  def transfer_from(text)
    m = text.match(/\ATRANSFER FROM\s+(?<name>.+)\z/)
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'TRANSFER-FROM',
                                           confidence: :high, internal: false, notes: nil)
  end

  # <account> : Closure Proceeds  -- fund's own fixed deposit maturing back into the account
  def closure_proceeds(text)
    m = text.match(/\A(?<account>\d{6,20})\s*:\s*Closure Proceeds\z/i)
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: nil, account_number: m[:account], pattern: 'FD-closure',
                                           confidence: :high, internal: true,
                                           notes: 'own fixed-deposit maturity, not an external investor deposit')
  end

  # TD/<account>/PRAVEGA... or BRN/TD/<account>/<date>/PRAVEGA... - an explicitly labelled
  # FD booking/rollover, so :high confidence is warranted.
  def fd_internal(text)
    return nil unless text.match?(%r{\A(?:BRN/)?TD/\d{6,20}/})

    BankDepositNarrationParser::Result.new(raw: text, name: nil, account_number: nil, pattern: 'FD-internal',
                                           confidence: :high, internal: true, notes: 'own fixed-deposit booking/rollover, not an external investor deposit')
  end

  # A bare numeric narration (no prefix at all) - observed in Axis statements as the next
  # rung of an FD ladder continuing a `TD/.../PRAVEGA...` row from earlier in the same
  # statement. Nothing about the narration's *shape* actually distinguishes that from a
  # coincidentally-numeric-only narration for a genuine external deposit, so this is a
  # weak, low-confidence guess, not a labelled signal like fd_internal above - kept as
  # `internal: true` (matching the real-data pattern this was built against) but flagged
  # for a reviewer to double-check rather than silently trusted.
  def fd_internal_bare_numeric(text)
    return nil unless text.match?(/\A\d{6,20}\z/)

    BankDepositNarrationParser::Result.new(raw: text, name: nil, account_number: text.strip, pattern: 'FD-internal-bare',
                                           confidence: :low, internal: true,
                                           notes: 'bare numeric narration assumed to be an FD ladder continuation (observed pattern, not a labelled ' \
                                                  'FD reference) - verify before trusting this classification')
  end

  # Loan Deposit/<ref>
  def loan_deposit(text)
    m = text.match(%r{\ALoan Deposit/(?<ref>\d+)\z}i)
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: nil, account_number: nil, pattern: 'Loan-deposit',
                                           confidence: :high, internal: true, notes: 'internal loan/OD deposit, not an external investor')
  end
end
