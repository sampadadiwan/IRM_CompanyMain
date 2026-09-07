# Narration shapes common enough across Indian banks' core-banking narration templates
# (slash-delimited RTGS/NEFT, bare TRF/) to serve as a first guess for a bank with no
# dedicated module yet — not tied to any one bank's quirks. Also the tail of every bank
# module's own dispatch chain, since Axis's real narrations already use this exact shape
# for RTGS/NEFT/TRF rows.
#
# Flat top-level class, not BankDepositNarrationParser::Fallback — see
# icici_narration_parser.rb for why (every services/ subdirectory here is its own
# Zeitwerk root).
module FallbackNarrationParser
  module_function

  def parse(text)
    slash_rtgs_neft(text) ||
      trf(text) ||
      BankDepositNarrationParser.unparsed(text)
  end

  # RTGS/<ref>/<name>/<bank...>  or  NEFT/<ref>/<name>/<bank...>
  def slash_rtgs_neft(text)
    m = text.match(%r{\A(?<kind>RTGS|NEFT)/(?<ref>[^/]+)/(?<name>[^/]+)(?:/.*)?\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: "#{m[:kind]}-slash",
                                           confidence: :medium, internal: false,
                                           notes: 'this bank does not expose remitter account number for RTGS/NEFT narrations')
  end

  # TRF/<name>/<desc>
  def trf(text)
    m = text.match(%r{\ATRF/(?<name>[^/]+)/.*\z})
    return nil unless m

    BankDepositNarrationParser::Result.new(raw: text, name: m[:name].strip, account_number: nil, pattern: 'TRF',
                                           confidence: :medium, internal: false, notes: 'no account number present in this narration format')
  end
end
