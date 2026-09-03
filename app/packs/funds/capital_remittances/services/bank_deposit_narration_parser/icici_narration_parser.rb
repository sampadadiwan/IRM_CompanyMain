# ICICI narration formats — hyphen-delimited: RTGS-<ref>-<name>-<account>-<ifsc>,
# BIL/INFT and CLG cheque-clearing narrations, and the MMT/IMPS + "TRFR FROM:" shorthands.
# Falls through to FallbackNarrationParser for anything that doesn't match — a narration
# ICICI shares with other banks (bare TRF/RTGS-slash/NEFT-slash conventions) is handled
# once there, not duplicated per bank.
#
# Flat top-level class, not BankDepositNarrationParser::Icici — this app's autoload config
# treats every directory under services/ as its own Zeitwerk root (see services/chat_providers/,
# services/digio/ for precedent), so a nested-namespace constant here would never resolve.
module IciciNarrationParser
  # A proper IFSC is 11 chars: 4 bank-code letters, a literal "0", 6 branch alnum chars.
  # Some narrations arrive with a truncated/malformed IFSC (observed: "HDFC00002" instead of
  # "HDFC0000240"), so match loosely on shape rather than requiring exactly 11 chars - it is
  # only used to locate where the name/account segment ends, and is never itself stored.
  IFSC_RE = /[A-Z]{4}\d[A-Z0-9]{3,6}/
  ACCOUNT_RE = /\A\d{6,20}\z/
  IFSC_TAIL_RE = /-(?<ifsc>#{IFSC_RE})\z/

  module_function

  def parse(text)
    hyphen_rtgs_neft(text) ||
      bil_inft(text) ||
      clg(text) ||
      mmt_imps(text) ||
      trfr_from(text) ||
      FallbackNarrationParser.parse(text)
  end

  # RTGS-<ref>-<name>-<account>-<ifsc>  or  NEFT-<ref>-<name>[-<desc>]-<account>-<ifsc>
  def hyphen_rtgs_neft(text)
    m = text.match(/\A(?<kind>RTGS|NEFT)-(?<body>.+)\z/)
    return nil unless m

    ifsc_m = m[:body].match(IFSC_TAIL_RE)
    return nil unless ifsc_m

    body_wo_ifsc = m[:body][0...ifsc_m.begin(0)]
    segments = body_wo_ifsc.split('-').map(&:strip).reject(&:empty?)
    return nil if segments.size < 2 # need at least ref + name

    _ref, *rest = segments
    name = rest.first
    tail = rest[1..] || [] # everything between name and IFSC - normally just the account, see below

    account, notes = account_from_tail(tail, total_segments: rest.size)

    # :high only for the clean "name-account" shape (nothing discarded, nothing merged) -
    # anything reconstructed or partially discarded is a best-effort guess, so :medium.
    confidence = if account && tail.size == 1 then :high
                 elsif account then :medium
                 else :low
                 end

    BankDepositNarrationParser::Result.new(raw: text, name: name, account_number: account, pattern: "#{m[:kind]}-hyphen",
                                           confidence: confidence, internal: false, notes: notes)
  end

  # Deutsche Bank and HSBC narrations sometimes embed hyphens *inside* the account number
  # itself, e.g. "0131201-00-3" or a foreign-account-style "IN HSBC 006-166516-906" (routing
  # prefix + split account) - so "last segment after the name" is not reliable when there's
  # more than one trailing segment. Instead scan from the end and keep pulling in segments as
  # long as they're purely numeric (once whitespace is stripped); a non-numeric segment (a
  # routing/branch code, or a NEFT UTR like "TRANSFER FROM RISHIC") stops the run and is
  # discarded. Concatenating the surviving run (in original order) reconstructs the account.
  def account_from_tail(tail, total_segments:)
    return [nil, nil] if tail.empty?

    digit_run_start = tail.length
    tail.reverse_each do |seg|
      break unless seg.gsub(/\s+/, '').match?(/\A\d+\z/)

      digit_run_start -= 1
    end
    digit_segments = tail[digit_run_start..]

    candidate = digit_segments.map { |s| s.gsub(/\s+/, '') }.join
    return [nil, "trailing segment(s) '#{tail.join('-')}' too short/non-numeric to be an account number; left blank for manual review"] unless digit_segments.any? && candidate.match?(ACCOUNT_RE)

    notes = if digit_segments.size > 1
              "account reconstructed from #{digit_segments.size} hyphen-split numeric segments " \
                "(#{digit_segments.join('-')}) - this bank embeds hyphens inside the account number, verify against statement"
            elsif digit_run_start.positive? # single trailing segment, but earlier junk segments were discarded
              "narration had #{total_segments} name/account segments; extra middle segments discarded"
            end

    [candidate, notes]
  end

  # BIL/INFT/<ref>/<name1>/<name2>  -> take the last, cleanest name segment
  def bil_inft(text)
    m = text.match(%r{\ABIL/INFT/(?<ref>[^/]+)/(?<seg1>[^/]*)/(?<seg2>.*)\z})
    return nil unless m

    name = m[:seg2].strip
    name = m[:seg1].strip if name.empty?
    return nil if name.empty? # both name segments blank - not actually parsed, fall through

    BankDepositNarrationParser::Result.new(raw: text, name: name, account_number: nil, pattern: 'BIL-INFT',
                                           confidence: :medium, internal: false, notes: 'no account number present in this narration format')
  end

  # CLG/<name>/<cheque_no>/<bank>/<clearing ref>
  def clg(text)
    m = text.match(%r{\ACLG/(?<name>[^/]+)/.*\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'CLG-cheque',
                                           confidence: :medium, internal: false,
                                           notes: 'cheque clearing narration; trailing digits are a clearing/instrument reference, not an account number')
  end

  # MMT/IMPS/<ref>/IMPS/<name>/<bank>
  def mmt_imps(text)
    m = text.match(%r{\AMMT/IMPS/(?<ref>[^/]+)/IMPS/(?<name>[^/]+)(?:/.*)?\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'MMT-IMPS',
                                           confidence: :low, internal: false, notes: 'IMPS name field is bank-truncated/abbreviated')
  end

  # TRFR FROM:<name>  or  TRFR FROM: <name>
  def trfr_from(text)
    m = text.match(/\ATRFR FROM:\s*(?<name>.+)\z/)
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'TRFR-FROM',
                                           confidence: :high, internal: false, notes: nil)
  end
end
